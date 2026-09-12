#!/usr/bin/env python3
"""Adapted from labs/R2-alb-behavior/app/server.py. Additions per R3's
approved scope: VERSION env var, /oom (memory-exhaustion), and /crash.

/crash was added after R3-04 investigation found `docker kill` does NOT
trigger Docker's `restart: on-failure` policy - Docker only auto-restarts
on a process exiting on its own, not on an externally issued kill/stop
(that distinction is real Docker behavior, not a bug). /crash makes the
process exit itself, which IS the correct way to demonstrate automatic
crash-recovery.
"""
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_NAME = os.environ.get("APP_NAME", "unknown")
VERSION = os.environ.get("VERSION", "2")
UNHEALTHY_FLAG = "/tmp/unhealthy"

_oom_ballast = []  # holds allocated memory so it isn't garbage-collected


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
        elif self.path == "/crash":
            self._write(200, f"crashing {APP_NAME} in 200ms\n")
            threading.Timer(0.2, lambda: os._exit(1)).start()
        elif self.path == "/oom":
            # Allocates 10MB chunks until the OS/cgroup kills the process.
            # Real memory pressure, real OOM kill - no simulation.
            try:
                while True:
                    _oom_ballast.append(bytearray(10 * 1024 * 1024))
            except MemoryError:
                self._write(500, "MemoryError before OOM-kill\n")
        else:
            self._write(200, f"Hello from {APP_NAME} VERSION={VERSION}\n")

    def log_message(self, fmt, *args):
        print(f"[{APP_NAME}] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
