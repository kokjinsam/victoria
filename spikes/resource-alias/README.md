# Experiment 6: Resource identity aliasing

**Question:** Can Victoria detect an HTTP server assigning the same ID to two distinct formal resources when all other observable attributes are identical?

The test uses real Apalache 0.58.3 ITF traces with two formal identities (`projectA`, `projectB`) and identical project names (`Same`). A healthy disposable HTTP server generates distinct UUIDs. The faulty server returns the first resource's UUID for both creations, while subsequent GET responses still satisfy expected name, status, and each symbol's self-consistent ID binding.

The workflow builds the unchanged pre-guard Rust client from commit `2fc9497d3c0c04682973d976ed44603239327225` and demonstrates that it **falsely passes** the faulty server. It then runs the updated Rust client against the same modeled behavior and confirms rejection when the second symbol is bound.

**Proposed invariant:** Different formal resource symbols must bind to different concrete IDs **when their OpenAPI Link target operation-and-parameter pairs overlap**. This is a scoped identity namespace, not global uniqueness of ID strings. Two distinct resource namespaces may both use `42` without a collision. The collision is classified as a behavioral conformance failure; a missing or invalid OpenAPI Link remains a binding/setup error.

This is not a finalized generic identity model. The formal trace still uses provisional `resourceSymbol` and `bindResource` variables, and the check cannot infer equivalence when the operation/parameter namespaces are disjoint but refer to the same underlying resource. No changes are made to the existing Elixir Victoria implementation.
