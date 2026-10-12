#!/usr/bin/env python3
"""Validate the projected trace only when tracee actually succeeds."""
import json
import sys

trace = json.load(open(sys.argv[1]))
assert "Double" in trace["vars"], trace["vars"]
actual = [int(state["Double"]["#bigint"]) for state in trace["states"]]
assert actual == [0, 2, 4], actual
print("TRACEE_PROJECTION_VALUES_PASS", actual)
