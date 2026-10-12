# Symbolic resource lifecycle: HTTP model-based conformance spike

This standalone experiment reuses the experimental Rust ITF/OpenAPI client at ../http-vertical.

A real Apalache 0.58.3 trace drives:
1. POST createProject -> 201; bind formal projectA to server-generated UUID using two OpenAPI Links.
2. GET getProject (symbol projectA) -> 200; verify concrete identity and modeled name.
3. DELETE deleteProject (symbol projectA) -> 200.
4. GET getProject (same symbol, still bound) -> 404.

The fault-injection server lies about DELETE success but retains the resource; the final GET returns 200 and the Rust client must fail.

This spike demonstrates exactly one symbolic resource and simple path parameter, NOT arbitrary model-to-runtime entity binding. The trace carries explicit bindResource, checkIdentity, and resourceSymbol metadata; that is a test convention, not a finalized protocol. The OpenAPI Link determines the path parameters of the GET and DELETE operations and captures $response.body#/id. Additional or ambiguous multi-resource cases remain open. The fixture's X-Actor is intentionally insecure, not authentication design.
