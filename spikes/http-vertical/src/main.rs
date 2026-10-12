use serde_json::{json, Map, Value};
use std::{collections::{HashMap, HashSet}, env, fs, process, time::Duration};
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};

fn read_arg(args: &[String], name: &str) -> Result<String, String> {
    args.windows(2)
        .find(|w| w[0] == name)
        .map(|w| w[1].clone())
        .ok_or_else(|| format!("missing required argument: {name}"))
}

fn decode_itf(v: &Value) -> Result<Value, String> {
    match v {
        Value::Object(m) if m.len() == 1 && m.contains_key("#bigint") => {
            let text = m["#bigint"].as_str().ok_or("malformed #bigint")?;
            let int: i64 = text.parse().map_err(|_| format!("integer out of spike range: {text}"))?;
            Ok(json!(int))
        }
        Value::Object(m) => {
            let mut out = Map::new();
            for (k, v) in m {
                if k == "#meta" { continue; }
                if k.starts_with('#') {
                    return Err(format!("unsupported ITF value in spike: {k}"));
                }
                out.insert(k.clone(), decode_itf(v)?);
            }
            Ok(Value::Object(out))
        }
        Value::Array(items) => Ok(Value::Array(
            items.iter().map(decode_itf).collect::<Result<Vec<_>, _>>()?,
        )),
        _ => Ok(v.clone()),
    }
}

fn projected_matches(expected: &Value, observed: &Value) -> bool {
    match (expected, observed) {
        (Value::Object(a), Value::Object(b)) => a.iter().all(|(key, value)| {
            b.get(key).is_some_and(|actual| projected_matches(value, actual))
        }),
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(x,y)| projected_matches(x,y))
        }
        _ => expected == observed,
    }
}

fn check_simple_schema(schema: &Value, body: &Value) -> Result<(), String> {
    if schema["type"] != "object" {
        return Err("spike supports only top-level object response schemas".into());
    }
    let object = body.as_object().ok_or("OpenAPI: response is not an object")?;
    if let Some(required) = schema.get("required").and_then(Value::as_array) {
        for key in required {
            let name = key.as_str().ok_or("invalid OpenAPI required key")?;
            if !object.contains_key(name) {
                return Err(format!("OpenAPI: missing required response field {name}"));
            }
        }
    }
    if let Some(props) = schema["properties"].as_object() {
        for (key, property) in props {
            if let Some(value) = object.get(key) {
                let valid = match property["type"].as_str() {
                    Some("boolean") => value.is_boolean(),
                    Some("string") => value.is_string(),
                    Some("integer") => value.as_i64().is_some(),
                    Some("object") => value.is_object(),
                    Some("array") => value.is_array(),
                    _ => return Err(format!("unsupported OpenAPI schema type for {key}")),
                };
                if !valid { return Err(format!("OpenAPI: invalid type for response field {key}")); }
            }
        }
    }
    Ok(())
}


#[derive(Debug, Clone)]
struct ResourceBinding {
    concrete_id: String,
    targets: HashSet<(String, String)>,
}
type Operations = HashMap<String, (String, String, Value)>;

fn bind_from_openapi_links(
    symbol: &str,
    response_spec: &Value,
    response_body: &Value,
    operations: &Operations,
    bindings: &mut HashMap<String, ResourceBinding>,
) -> Result<(), String> {
    if bindings.contains_key(symbol) {
        return Err(format!("BINDING ERROR: symbol {symbol} already bound"));
    }
    let links = response_spec["links"].as_object()
        .ok_or_else(|| format!("BINDING ERROR: response has no OpenAPI Links for {symbol}"))?;
    let mut id: Option<String> = None;
    let mut targets = HashSet::new();
    for (link_name, link) in links {
        let operation = link["operationId"].as_str()
            .ok_or_else(|| format!("BINDING ERROR: link {link_name} lacks operationId"))?;
        let (_, target_path, target_op) = operations.get(operation)
            .ok_or_else(|| format!("BINDING ERROR: link targets unknown operation {operation}"))?;
        let parameters = link["parameters"].as_object()
            .ok_or_else(|| format!("BINDING ERROR: link {link_name} lacks parameters"))?;
        for (param_name, expression) in parameters {
            let name = param_name.strip_prefix("path.")
                .ok_or_else(|| format!("BINDING ERROR: unsupported Link parameter {param_name}"))?;
            let target = format!("{{{name}}}");
            let declared = target_op["parameters"].as_array().is_some_and(|params| {
                params.iter().any(|p| p["in"] == "path" && p["name"] == name)
            });
            if !target_path.contains(&target) || !declared {
                return Err(format!("BINDING ERROR: {operation} has no declared path parameter {name}"));
            }
            let expr = expression.as_str()
                .ok_or_else(|| format!("BINDING ERROR: non-string Link expression for {name}"))?;
            let pointer = expr.strip_prefix("$response.body#")
                .ok_or_else(|| format!("BINDING ERROR: unsupported runtime expression {expr}"))?;
            if !pointer.starts_with('/') {
                return Err(format!("BINDING ERROR: expected JSON pointer, got {expr}"));
            }
            let value = response_body.pointer(pointer)
                .and_then(Value::as_str).filter(|s| !s.is_empty())
                .ok_or_else(|| format!("BINDING ERROR: response cannot resolve {expr}"))?;
            if let Some(previous) = &id {
                if previous != value {
                    return Err(format!("BINDING ERROR: conflicting Link values for {symbol}"));
                }
            } else {
                id = Some(value.to_owned());
            }
            targets.insert((operation.to_owned(), name.to_owned()));
        }
    }
    let concrete_id = id.ok_or_else(|| format!("BINDING ERROR: no resolvable Links for {symbol}"))?;
    if targets.is_empty() {
        return Err(format!("BINDING ERROR: no usable target operations for {symbol}"));
    }
    println!("BIND {symbol} using {} OpenAPI Link target(s)", targets.len());
    bindings.insert(symbol.to_owned(), ResourceBinding { concrete_id, targets });
    Ok(())
}

fn render_http_path(
    path_template: &str,
    operation: &str,
    op: &Value,
    state: &Value,
    bindings: &HashMap<String, ResourceBinding>,
) -> Result<String, String> {
    if !path_template.contains('{') {
        return Ok(path_template.to_owned());
    }
    let params = op["parameters"].as_array()
        .ok_or_else(|| format!("BINDING ERROR: {operation} lacks path parameters"))?;
    let symbol = state["resourceSymbol"].as_str()
        .ok_or_else(|| format!("BINDING ERROR: missing resourceSymbol for {operation}"))?;
    let binding = bindings.get(symbol)
        .ok_or_else(|| format!("BINDING ERROR: unresolved symbolic identity {symbol}"))?;
    let mut path = path_template.to_owned();
    let mut seen = false;
    for parameter in params.iter().filter(|p| p["in"] == "path") {
        let name = parameter["name"].as_str()
            .ok_or_else(|| "BINDING ERROR: path parameter has no name".to_owned())?;
        if !binding.targets.contains(&(operation.to_owned(), name.to_owned())) {
            return Err(format!("BINDING ERROR: {symbol} has no OpenAPI Link for {operation}.{name}"));
        }
        let target = format!("{{{name}}}");
        if !path.contains(&target) {
            return Err(format!("BINDING ERROR: template lacks declared parameter {name}"));
        }
        let encoded = utf8_percent_encode(&binding.concrete_id, NON_ALPHANUMERIC).to_string();
        path = path.replace(&target, &encoded);
        seen = true;
    }
    if !seen || path.contains('{') || path.contains('}') {
        return Err(format!("BINDING ERROR: unresolved path template for {operation}"));
    }
    Ok(path)
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    let itf_path = read_arg(&args, "--trace")?;
    let openapi_path = read_arg(&args, "--openapi")?;
    let base_url = read_arg(&args, "--url")?;
    let itf: Value = serde_json::from_str(&fs::read_to_string(&itf_path).map_err(|e| e.to_string())?)
        .map_err(|e| format!("invalid ITF JSON: {e}"))?;
    if itf.get("loop").is_some() { return Err("lasso traces unsupported by this spike".into()); }
    let states = itf["states"].as_array().ok_or("ITF missing states")?;
    if states.len() < 2 { return Err("ITF contains no transitions".into()); }
    if states[0]["operationId"] != "Initial" {
        return Err("ITF first state must be Initial".into());
    }

    let yaml: serde_yaml::Value = serde_yaml::from_str(
        &fs::read_to_string(&openapi_path).map_err(|e| e.to_string())?
    ).map_err(|e| format!("invalid OpenAPI YAML: {e}"))?;
    let spec = serde_json::to_value(yaml).map_err(|e| e.to_string())?;
    let mut ops: HashMap<String, (String, String, Value)> = HashMap::new();
    let paths = spec["paths"].as_object().ok_or("OpenAPI has no paths")?;
    for (path, path_item) in paths {
        for (method, op) in path_item.as_object().ok_or("invalid OpenAPI path item")? {
            if !["get", "post", "put", "patch", "delete"].contains(&method.as_str()) { continue; }
            if let Some(id) = op["operationId"].as_str() {
                if ops.insert(id.into(), (method.to_uppercase(), path.clone(), op.clone())).is_some() {
                    return Err(format!("duplicate OpenAPI operationId: {id}"));
                }
            }
        }
    }

    // Only one apiKey-in-header scheme is supported by the experiment.
    let schemes = spec.pointer("/components/securitySchemes")
        .and_then(Value::as_object).ok_or("OpenAPI missing securitySchemes")?;
    let headers: Vec<&str> = schemes.values().filter_map(|scheme| {
        if scheme["type"] == "apiKey" && scheme["in"] == "header" {
            scheme["name"].as_str()
        } else { None }
    }).collect();
    if headers.len() != 1 { return Err("spike requires exactly one header API key scheme".into()); }
    let auth_header = headers[0];
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(10)).build();
    let mut bindings: HashMap<String, ResourceBinding> = HashMap::new();

    for (index, raw_state) in states.iter().enumerate().skip(1) {
        let state = decode_itf(raw_state)?;
        let op_id = state["operationId"].as_str().ok_or("missing operationId")?;
        let actor = state["actor"].as_str().ok_or("missing actor")?;
        let status_expected = state["expectedStatus"].as_u64().ok_or("missing expectedStatus")? as u16;
        let (method, path, op) = ops.get(op_id)
            .ok_or_else(|| format!("unknown OpenAPI operationId: {op_id}"))?;
        let concrete_path = render_http_path(path, op_id, op, &state, &bindings)?;
        let url = format!("{}{}", base_url.trim_end_matches('/'), concrete_path);
        let request = agent.request(method, &url).set(auth_header, actor);
        let result = if op.get("requestBody").is_some() {
            request.send_json(state["requestBody"].clone())
        } else { request.call() };
        let response = match result {
            Ok(r) => r,
            Err(ureq::Error::Status(_, r)) => r,
            Err(e) => return Err(format!("TRANSPORT ERROR at step {index}: {e}")),
        };
        let status_actual = response.status();
        let content_type = response.header("Content-Type").unwrap_or("").to_owned();
        let body_str = response.into_string().map_err(|e| e.to_string())?;
        let body: Value = if body_str.is_empty() {
            Value::Null
        } else {
            serde_json::from_str(&body_str)
                .map_err(|e| format!("invalid HTTP response JSON: {e}"))?
        };
        let response_spec = op["responses"].get(status_actual.to_string())
            .ok_or_else(|| format!("OPENAPI FAILURE step {index}: undocumented status {status_actual}"))?;
        if response_spec.get("content").is_some() {
            if !content_type.starts_with("application/json") {
                return Err(format!("OPENAPI FAILURE step {index}: unexpected content type {content_type}"));
            }
            let schema = &response_spec["content"]["application/json"]["schema"];
            check_simple_schema(schema, &body)
                .map_err(|e| format!("OPENAPI FAILURE step {index}: {e}"))?;
        } else if body != Value::Null {
            return Err(format!("OPENAPI FAILURE step {index}: unexpected response body"));
        }
        if status_actual != status_expected {
            return Err(format!("CONFORMANCE FAIL step {index} {op_id}: expected status {status_expected}, got {status_actual}"));
        }
        if state["checkBody"] == true
            && !projected_matches(&state["expectedBody"], &body) {
                return Err(format!("CONFORMANCE FAIL step {index} {op_id}: expected projected {}, observed {}",
                    state["expectedBody"], body));
        }
        if state["checkIdentity"] == true {
            let symbol = state["resourceSymbol"].as_str()
                .ok_or("BINDING ERROR: missing resourceSymbol for identity check")?;
            let binding = bindings.get(symbol)
                .ok_or_else(|| format!("BINDING ERROR: unresolved symbol {symbol}"))?;
            if body["id"].as_str() != Some(binding.concrete_id.as_str()) {
                return Err(format!("CONFORMANCE FAIL step {index} {op_id}: wrong resource identity for {symbol}"));
            }
        }
        if state["bindResource"] == true {
            let symbol = state["resourceSymbol"].as_str()
                .ok_or("BINDING ERROR: missing resourceSymbol for creation")?;
            bind_from_openapi_links(symbol, response_spec, &body, &ops, &mut bindings)?;
        }
        println!("PASS step {index}: {op_id} status={status_actual} observed={}", state["checkBody"]);
    }
    println!("PASS: {} trace transitions conformed", states.len() - 1);
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_link_and_restricts_to_declared_target() {
        let mut operations = HashMap::new();
        let get = json!({"parameters": [{"name":"project_id","in":"path","required":true}]});
        operations.insert("getProject".into(), ("GET".into(), "/projects/{project_id}".into(), get));
        let response_spec = json!({"links":{"project":{
            "operationId":"getProject",
            "parameters":{"path.project_id":"$response.body#/id"}
        }}});
        let mut bindings = HashMap::new();
        bind_from_openapi_links("projectA", &response_spec, &json!({"id":"uuid-1"}),
            &operations, &mut bindings).unwrap();
        let state = json!({"resourceSymbol":"projectA"});
        let (method, template, op) = operations.get("getProject").unwrap();
        assert_eq!(method, "GET");
        assert_eq!(render_http_path(template, "getProject", op, &state, &bindings).unwrap(),
            "/projects/uuid%2D1");
        assert!(render_http_path(template, "deleteProject", op, &state, &bindings).is_err());
    }

    #[test]
    fn missing_link_pointer_is_not_a_conformance_failure() {
        let mut operations = HashMap::new();
        operations.insert("getProject".into(), ("GET".into(),
            "/projects/{project_id}".into(),
            json!({"parameters":[{"in":"path","name":"project_id"}]})));
        let bad = json!({"links":{"project":{
            "operationId":"getProject",
            "parameters":{"path.project_id":"$response.body#/absent"}
        }}});
        let mut bindings = HashMap::new();
        let err = bind_from_openapi_links("projectA", &bad, &json!({"id":"uuid-1"}),
            &operations, &mut bindings).unwrap_err();
        assert!(err.starts_with("BINDING ERROR:"), "{err}");
        assert!(bindings.is_empty());
    }

    #[test]
    fn decodes_itf_bigint() {
        assert_eq!(decode_itf(&json!({"#bigint":"403"})).unwrap(), json!(403));
    }
    #[test]
    fn projected_records_are_partial_but_arrays_are_exact() {
        assert!(projected_matches(&json!({"count":0}), &json!({"count":0,"extra":"ok"})));
        assert!(!projected_matches(&json!({"count":0}), &json!({"count":1,"extra":"ok"})));
        assert!(!projected_matches(&json!({"items":[1,2]}), &json!({"items":[2,1]})));
    }
}
