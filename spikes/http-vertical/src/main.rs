use serde_json::{json, Map, Value};
use std::{collections::HashMap, env, fs, process, time::Duration};

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

    for (index, raw_state) in states.iter().enumerate().skip(1) {
        let state = decode_itf(raw_state)?;
        let op_id = state["operationId"].as_str().ok_or("missing operationId")?;
        let actor = state["actor"].as_str().ok_or("missing actor")?;
        let status_expected = state["expectedStatus"].as_u64().ok_or("missing expectedStatus")? as u16;
        let (method, path, op) = ops.get(op_id)
            .ok_or_else(|| format!("unknown OpenAPI operationId: {op_id}"))?;
        if path.contains('{') {
            return Err("path template binding deliberately not implemented in first spike".into());
        }
        let url = format!("{}{}", base_url.trim_end_matches('/'), path);
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
        let body: Value = serde_json::from_str(&body_str)
            .map_err(|e| format!("invalid HTTP response JSON: {e}"))?;
        let response_spec = op["responses"].get(status_actual.to_string())
            .ok_or_else(|| format!("OPENAPI FAILURE step {index}: undocumented status {status_actual}"))?;
        if !content_type.starts_with("application/json") {
            return Err(format!("OPENAPI FAILURE step {index}: unexpected content type {content_type}"));
        }
        let schema = &response_spec["content"]["application/json"]["schema"];
        check_simple_schema(schema, &body)
            .map_err(|e| format!("OPENAPI FAILURE step {index}: {e}"))?;
        if status_actual != status_expected {
            return Err(format!("CONFORMANCE FAIL step {index} {op_id}: expected status {status_expected}, got {status_actual}"));
        }
        if state["checkBody"] == true
            && !projected_matches(&state["expectedBody"], &body) {
                return Err(format!("CONFORMANCE FAIL step {index} {op_id}: expected projected {}, observed {}",
                    state["expectedBody"], body));
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
