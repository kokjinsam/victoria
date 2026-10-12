#!/usr/bin/env python3
"""Disposable HTTP fixture; --fault keeps the resource after successful deletion."""
import argparse
import json
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

p = argparse.ArgumentParser()
p.add_argument("--port", type=int, default=8124)
p.add_argument("--fault", action="store_true")
args = p.parse_args()
projects = {}

class API(BaseHTTPRequestHandler):
    def reply(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path != "/projects" or self.headers.get("X-Actor") != "admin":
            return self.reply(404, {"error": "not found"})
        n = int(self.headers.get("Content-Length", "0"))
        name = json.loads(self.rfile.read(n))["name"]
        ident = str(uuid.uuid4())
        projects[ident] = name
        return self.reply(201, {"id": ident, "name": name})

    def do_GET(self):
        if not self.path.startswith("/projects/"):
            return self.reply(404, {"error": "not found"})
        ident = unquote(self.path[len("/projects/"):])
        if ident not in projects:
            return self.reply(404, {"error": "not found"})
        return self.reply(200, {"id": ident, "name": projects[ident], "extra": "allowed"})

    def do_DELETE(self):
        if not self.path.startswith("/projects/"):
            return self.reply(404, {"error": "not found"})
        ident = unquote(self.path[len("/projects/"):])
        if ident not in projects:
            return self.reply(404, {"error": "not found"})
        if not args.fault:
            del projects[ident]
        return self.reply(200, {"deleted": True})

    def log_message(self, *_):
        pass

ThreadingHTTPServer(("127.0.0.1", args.port), API).serve_forever()
