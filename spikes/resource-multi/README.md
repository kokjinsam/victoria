# Victoria multi-resource identity experiment

Experimental only; does not change Victoria's Elixir package.

Two real Apalache 0.58.3 traces are generated from one TLA+ module with InitAlpha and InitBeta. Each creates two resources of the same type, alternating creation order, before querying and deleting specific symbolic resources. Both cases use the same Rust CLI and the same OpenAPI document as the earlier single-resource spike.

The 7 HTTP operations in each trace are: create first, create second, get second, get first, delete first, get second, get deleted first.

The server generates fresh UUIDs. The Rust runner binds each to projectA or projectB by reading the create operation's OpenAPI response Links, then uses the bound ID with supported GET/DELETE path parameters.

The fixture includes negative cases:
- GET returns the wrong ID with the correct name (identity checking).
- DELETE reports success but deletes the other project (cross-resource preservation).
- Two POSTs return a reused ID (resource aliasing).
- OpenAPI omits Links (binding/setup error).
- OpenAPI Links contain conflicting capture expressions (binding/setup error).

No mandatory Victoria YAML, app-specific Rust adapter, or hand-authored ITF is involved. The formal model still provides resourceSymbol and bindResource fields. OpenAPI Links do not independently determine which formal symbol owns a created resource.

This does not test resource graphs, multiple ID field mappings, real authentication, arbitrary parameter serialization, concurrent requests, or nondeterministic models.
