import argparse, json, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote
p=argparse.ArgumentParser()
p.add_argument("--port",type=int,required=True)
p.add_argument("--alternate",choices=["same","different"],required=True)
a=p.parse_args()
db={}
primary=None
class App(BaseHTTPRequestHandler):
    def send(self,s,d):
        data=json.dumps(d).encode()
        self.send_response(s)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_POST(self):
        global primary
        if self.headers.get("X-Actor")!="admin":
            return self.send(403,{"error":"forbidden"})
        n=int(self.headers.get("Content-Length","0"))
        name=json.loads(self.rfile.read(n))["name"]
        if self.path=="/projects":
            ident=str(uuid.uuid4())
            primary=ident
        elif self.path=="/references" and primary is not None:
            ident=primary if a.alternate=="same" else str(uuid.uuid4())
        else:
            return self.send(404,{"error":"not found"})
        db[ident]=name
        self.send(201,{"id":ident,"name":name})
    def do_GET(self):
        if self.path.startswith("/projects/"):
            ident=unquote(self.path[10:])
        elif self.path.startswith("/references/"):
            ident=unquote(self.path[12:])
        else:
            return self.send(404,{"error":"not found"})
        if ident not in db:
            return self.send(404,{"error":"not found"})
        self.send(200,{"id":ident,"name":db[ident]})
    def log_message(self,*args):
        pass
ThreadingHTTPServer(("127.0.0.1",a.port),App).serve_forever()
