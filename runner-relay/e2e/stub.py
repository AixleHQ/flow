#!/usr/bin/env python3
"""A stand-in for the Rails platform, for the relay's browser-path end-to-end run.

It answers only what the relay and Traefik ask of the platform:
  GET  /api/v1/internal/ws_auth                          (terminal-auth; viewer = the `viewer` cookie)
  GET  /api/v1/internal/runner_relay/holders/:token      (the relay's registry miss)
  POST /api/v1/internal/runner_relay/checks              (the relay's reconcile pass)
Control files in /tmp/e2e/ctl: `invalid` makes checks answer false, `session_gone` makes holders
answer that no machine holds the session.
"""
import json, os, re, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "e2eroutetoken0123456789abcdef00"
SESSION, ENVIRONMENT = 555, 42
PORTS = {"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041, "ide": 8443}
INTERNAL = "Bearer e2e-internal-token"
CTL = "/tmp/e2e/ctl"
OWNER_ONLY = {"tty", "ide", "upload"}


def flag(name):
    return os.path.exists(os.path.join(CTL, name))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(self.command, self.path.split("?")[0], file=sys.stderr, flush=True)

    def reply(self, status, body=b"", headers=None):
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def json(self, status, value):
        self.reply(status, json.dumps(value).encode(), {"Content-Type": "application/json"})

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/v1/internal/ws_auth":
            return self.ws_auth()
        m = re.fullmatch(r"/api/v1/internal/runner_relay/holders/([^/]+)", path)
        if m:
            if self.headers.get("Authorization") != INTERNAL:
                return self.reply(401)
            if m.group(1) != TOKEN:
                return self.reply(404)
            holder = None if flag("session_gone") else ENVIRONMENT
            return self.json(200, {"session_id": SESSION, "environment_id": holder, "state": "ready", "ports": PORTS})
        self.reply(404)

    def do_POST(self):
        if self.path != "/api/v1/internal/runner_relay/checks":
            return self.reply(404)
        if self.headers.get("Authorization") != INTERNAL:
            return self.reply(401)
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        answers = [
            (not flag("invalid")) and m["environment_id"] == ENVIRONMENT and m.get("session_id") == SESSION
            for m in body["machines"]
        ]
        self.json(200, {"machines": answers})

    def ws_auth(self):
        m = re.match(r"^/t/([^/]+)/([^/?]+)", self.headers.get("X-Forwarded-Uri", ""))
        if not m or m.group(1) != TOKEN:
            return self.reply(404)
        cookie = self.headers.get("Cookie", "")
        viewer = re.search(r"(?:^|;\s*)viewer=(owner|guest)", cookie)
        if not viewer:
            return self.reply(401)
        if viewer.group(1) == "guest" and m.group(2) in OWNER_ONLY:
            return self.reply(403)
        pairs = [p.strip() for p in cookie.split(";") if re.match(r"\s*vscode-[\w-]+=", p)]
        headers = {"X-User-Id": "1" if viewer.group(1) == "owner" else "2", "X-Session-Id": str(SESSION)}
        if pairs:
            headers["Cookie"] = "; ".join(pairs)
        self.reply(200, b"", headers)


ThreadingHTTPServer(("0.0.0.0", 4000), Handler).serve_forever()
