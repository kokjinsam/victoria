#!/usr/bin/env python3
"""Disposable HTTP SUT with a deliberate hidden mutation defect option."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=8123)
parser.add_argument("--fault", action="store_true")
args = parser.parse_args()

state = {"member_active": True, "projects": []}

class API(BaseHTTPRequestHandler):
    def respond(self, status, obj):
        content = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_POST(self):
        actor = self.headers.get("X-Actor")
        if self.path == "/members/member/deactivate" and actor == "admin":
            state["member_active"] = False
            return self.respond(200, {"active": False})
        if self.path == "/projects" and actor == "member":
            size = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(size))
            if not state["member_active"]:
                if args.fault:
                    state["projects"].append(data["name"])  # Hidden defect: mutates despite 403.
                return self.respond(403, {"error": "forbidden"})
            state["projects"].append(data["name"])
            return self.respond(201, {"id": str(len(state["projects"]))})
        return self.respond(404, {"error": "unknown"})

    def do_GET(self):
        if self.path == "/projects" and self.headers.get("X-Actor") == "admin":
            return self.respond(200, {"count": len(state["projects"]), "extra": "allowed"})
        return self.respond(404, {"error": "unknown"})

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", args.port), API).serve_forever()
