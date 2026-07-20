# Apalache v0.58.3 characterization

This directory records the direct CLI characterization used to freeze Victoria Phase 1.2. The observations
were made on July 19, 2026 with the asdf-installed `apalache-mc` v0.58.3 (`build: f4ac7ff`). Commands used
absolute source, config, and run-directory paths, inherited the caller environment, and did not use a shell
wrapper around Apalache.

## Observations

| Scenario | Exit status | Observed run-directory artifacts |
| --- | ---: | --- |
| `apalache-mc version` | 0 | Exact output `0.58.3\n` |
| Pre-created empty `--run-dir` | 0 | Accepted for both `simulate` and `check`; Apalache populated the existing directory |
| Pre-created nonempty `--run-dir` containing `victoria-run.json` | 0 | Placeholder manifest survived byte-for-byte unchanged; normal artifacts and `example.itf.json` plus `example1.itf.json` were produced |
| `simulate --length=3 --max-run=1 --output-traces` | 0 | Top-level regular `example.itf.json` and `example1.itf.json` |
| `simulate --length=3 --max-run=3 --output-traces` | 0 | Top-level regular `example.itf.json` and `example1.itf.json` through `example3.itf.json` |
| Successful `check --length=3 --output-traces` | 0 | Top-level regular `example.itf.json` and `example0.itf.json` |
| Invariant-violating `check --length=3 --output-traces` | 12 | Top-level regular `violation.itf.json` and `violation1.itf.json` |
| Malformed TLA+ | 255 | `detailed.log` and `run.txt`; no ITF trace |
| Config naming a missing specification operator | 255 | `detailed.log` and `run.txt`; no ITF trace |
| `simulate --length=0 --max-run=1 --output-traces` | 0 | `example.itf.json` and `example1.itf.json`, each containing only state zero |

The ITF files above were actual top-level regular files in the requested run directory. The duplicate
unindexed/indexed file naming is an Apalache behavior; Victoria therefore discovers every matching file and
does not infer a trace count from `max-run`. Apalache's diagnostics also name its auxiliary
`_apalache-out/<source>/<run>` workspace beneath the process working directory. Victoria treats only the
exclusively reserved `--run-dir` as its materialization boundary and does not search that auxiliary tree.

The checked and simulated traces had no `loop` member. A real lasso-producing v0.58.3 input was not readily
available in this characterization, so no claim about real lasso naming is made. The existing synthetic ITF
lasso fixture continues to characterize materialization without changing Runner's rejection of lasso replay.

## Inputs

- `../specs/Counter.tla` and `../specs/Counter.cfg` cover successful simulation and checking.
- `Violation.tla` and `Violation.cfg` produce the status-12 invariant counterexample.
- `Malformed.tla` and `Malformed.cfg` cover source and configuration rejection without traces.

These observations support exclusive pre-creation of the exact planned run directory and top-level,
lexically sorted, `File.lstat/1`-based discovery of names ending exactly in `.itf.json`.

The nonempty-directory characterization was repeated on July 20, 2026 with this direct invocation after
writing `{"placeholder":"victoria phase 1.2.1"}\n` to the requested run directory:

```sh
apalache-mc simulate \
  --config=/Users/sammkj/Developer/packages/victoria/test/specs/Counter.cfg \
  --length=3 \
  --max-run=1 \
  --output-traces \
  --run-dir="$run_directory" \
  /Users/sammkj/Developer/packages/victoria/test/specs/Counter.tla
```

The command exited 0. The manifest's SHA-256 was
`e37db520a630551d848981f64e7ccf58ff87c88fbb37c2a5559e41abaf012f83` both before and after execution.
Apalache also wrote its normal logs, generated source artifacts, and two top-level ITF traces. This proves
that v0.58.3 tolerates Victoria committing a running manifest before process execution.
