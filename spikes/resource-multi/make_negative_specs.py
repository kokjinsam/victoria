#!/usr/bin/env python3
"""Generate two negative OpenAPI fixtures using bounded, asserted text transforms."""
from pathlib import Path
import sys
source, out = map(Path, sys.argv[1:])
text = source.read_text()
start_token = "          links:\n"
next_path = "  /projects/{project_id}:\n"
assert text.count(start_token) == 1
start = text.index(start_token)
end = text.index(next_path, start)
assert text[start:end].count("$response.body#/id") == 2
out.mkdir(parents=True, exist_ok=True)
(out / "without-links.yaml").write_text(text[:start] + text[end:])
conflict = text.replace('path.project_id: "$response.body#/id"',
                        'path.project_id: "$response.body#/name"', 1)
assert conflict != text and conflict.count("$response.body#/id") == 1
(out / "conflicting-links.yaml").write_text(conflict)
print("OPENAPI_NEGATIVE_FIXTURES_CREATED")
