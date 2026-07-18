# Victoria Agent Guidelines

Victoria is model-based testing lib with Apalache TLA+ model checker.

## Development

Use the project's Mix aliases whenever possible.

```sh
mix deps.get
mix compile
mix test
mix format
```

Preferred full check:

```sh
mix check
```

Current full CI alias includes:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
```

## Guidelines

- Keep output formats stable for downstream tools.
- Do not publish, tag, or bump versions unless explicitly requested.
