#!/usr/bin/env python3
"""Two-resource HTTP API with independent faults; X-Actor is a disposable fixture."""
import argparse
import json
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

p = argparse.ArgumentParser()
p.add_argument("--port", type=int, required=True)
p.add_argument("--fault", choices=["none", "cross-id", "delete-other", "alias-create"], default="none")
args = p.parse_args()
projects = {}

class API(BaseHTTPRequestHandler):
    def reply(self, status, data):
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path != "/projects" or self.headers.get("X-Actor") != "admin":
            return self.reply(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", "0"))
        name = json.loads(self.rfile.read(length))["name"]
        if args.fault == "alias-create" and projects:
            ident = next(iter(projects))
        else:
            ident = str(uuid.uuid4())
        projects[ident] = name
        return self.reply(201, {"id": ident, "name": name})

    def do_GET(self):
        if not self.path.startswith("/projects/"):
            return self.reply(404, {"error": "not found"})
        ident = unquote(self.path[len("/projects/"):])
        if ident not in projects:
            return self.reply(404, {"error": "not found"})
        observed_id = ident
        if args.fault == "cross-id" and len(projects) > 1:
            observed_id = next(other for other in projects if other != ident)
        return self.reply(200, {"id": observed_id, "name": projects[ident], "extra": "allowed"})

    def do_DELETE(self):
        if not self.path.startswith("/projects/"):
            return self.reply(404, {"error": "not found"})
        ident = unquote(self.path[len("/projects/"):])
        if ident not in projects:
            return self.reply(404, {"error": "not found"})
        if args.fault == "delete-other" and len(projects) > 1:
            actual_target = next(other for other in projects if other != ident)
        else:
            actual_target = ident
        del projects[actual_target]
        return self.reply(200, {"deleted": True})

    def log_message(self, *_args):
        pass

ThreadingHTTPServer(("127.0.0.1", args.port), API).serve_forever()
