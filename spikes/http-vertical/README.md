# HTTP model-based testing vertical spike

**Experimental only.** This is an isolated Rust/Apalache/OpenAPI integration experiment, not the production Victoria CLI.

- \`WorkspaceHTTP.tla\` is a small deterministic model with three actions:
  \`deactivateMember\` (200), \`createProject\` by a deactivated member (403), and
  \`listProjects\` as an explicit observation (200; projected \`count = 0\`).
- Apalache 0.58.3 generates a **real** four-state ITF trace.
- A Rust binary parses ITF, resolves \`operationId\` in OpenAPI, issues HTTP requests,
  checks documented response statuses and a **minimal subset** of object schemas, and
  compares a partial modeled JSON response where \`checkBody = TRUE\`.
- The mock Python HTTP server has an optional bug: it mutates projects despite
  returning HTTP 403. The following GET should expose this.
- The workflow runs a correct and a faulty server from separate fresh processes,
  and treats detection of the faulty server as an expected successful test.
- The workflow also attempts Apalache \`tracee\` for \`VisibleCount\`, but records
  its result independently rather than assuming it works.

**Not implemented:** full OpenAPI validation, path/query serialization, real credentials,
symbolic ID capture, generic type-directed set/sequence comparison, nondeterminism,
initial-state verification, trace reset providers or reliable asynchronous observations.

The SUT's \`X-Actor\` header is an **insecure disposable fixture**, not a proposed
authentication design.

To reproduce on a machine with Rust, Python, and Apalache 0.58.3:
generate an ITF trace with \`apalache-mc simulate --length=3 --max-run=1 --output-traces=true --run-dir=/tmp/victoria-spike WorkspaceHTTP.tla\`,
start \`python3 server.py\`, then run:
\`cargo run -- --trace /path/to/example0.itf.json --openapi openapi.yaml --url http://127.0.0.1:8123\`.

The original Elixir implementation is deliberately left unchanged.
