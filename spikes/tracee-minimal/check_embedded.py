#!/usr/bin/env python3
"""Assert actual generated traces rather than hand-authored ITF substitutes."""
import json
import pathlib
import sys

pure_path, embedded_path = map(pathlib.Path, sys.argv[1:])
pure = json.loads(pure_path.read_text())
embedded = json.loads(embedded_path.read_text())

def integers(trace, var):
    return [int(state[var]["#bigint"]) for state in trace["states"]]

assert pure["vars"] == ["count"], pure["vars"]
assert set(embedded["vars"]) == {"count", "expectedDouble"}, embedded["vars"]
assert integers(pure, "count") == [0, 1, 2]
assert integers(embedded, "count") == [0, 1, 2]
assert integers(embedded, "expectedDouble") == [0, 2, 4]
print("PURE_GENERATED_TRACE_PASS", pure_path.stat().st_size, "bytes")
print("EMBEDDED_GENERATED_TRACE_PASS", embedded_path.stat().st_size, "bytes")
print("EMBEDDED_EXPECTATIONS", integers(embedded, "expectedDouble"))
