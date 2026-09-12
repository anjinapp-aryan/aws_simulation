#!/usr/bin/env python3
"""Minimal self-identifying HTTP server with an independently-toggleable
health endpoint. Built only because the reuse audit found no existing tiny
demo server (traefik/whoami included) that supports flipping /health to
unhealthy while / keeps responding - the one behavior R2's Experiment 5
needs and no off-the-shelf project provides. ~30 lines, no framework.
"""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_NAME = os.environ.get("APP_NAME", "unknown")
UNHEALTHY_FLAG = "/tmp/unhealthy"


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/health":
            if os.path.exists(UNHEALTHY_FLAG):
                self._write(500, f"UNHEALTHY ({APP_NAME})\n")
            else:
                self._write(200, f"healthy ({APP_NAME})\n")
        else:
            self._write(200, f"Hello from {APP_NAME}\n")

    def log_message(self, fmt, *args):
        print(f"[{APP_NAME}] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
