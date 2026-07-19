# Trace fixtures

Files in this directory are untouched output from the pinned model checker. Synthetic and malformed
inputs belong in `test/fixtures`.

`counter.itf.json` was generated with Apalache 0.58.3 (`apalache-mc version` returned `0.58.3`) from
`test/specs/Counter.tla` and `test/specs/Counter.cfg` by this successful command, run from the repository
root:

```sh
apalache-mc --out-dir=tmp/apalache simulate --config=test/specs/Counter.cfg --length=3 --max-run=1 --output-traces test/specs/Counter.tla
```

The generated `example1.itf.json` was copied byte-for-byte to `test/traces/counter.itf.json`. Its SHA-256
digest is `a7ae8c6f780bc264437fc9675139b6f5940dcbc5efe91852cb2d622cfaddab86`.
