#!/usr/bin/env python3
"""R10 app - same minimal-server pattern used in every prior phase
(R2's health toggle, R6/R7/R9's endpoint style). Kubernetes is the new
orchestrator here, not a new application framework.

/          - identifies which pod served the request (real pod name via
             HOSTNAME, which Kubernetes sets to the real pod name) - used
             for R10-08 service-discovery evidence.
/health    - LIVENESS probe target. Independently toggleable via
             /tmp/unhealthy-liveness.
/ready     - READINESS probe target. Independently toggleable via
             /tmp/unhealthy-ready.
/version   - returns APP_VERSION env var, used for R10-03 rolling deploy.
"""
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POD_NAME = os.environ.get("HOSTNAME", socket.gethostname())
APP_VERSION = os.environ.get("APP_VERSION", "v1")
LIVENESS_FLAG = "/tmp/unhealthy-liveness"
READINESS_FLAG = "/tmp/unhealthy-ready"


class Handler(BaseHTTPRequestHandler):
    def _write(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/health":
            if os.path.exists(LIVENESS_FLAG):
                self._write(500, f"LIVENESS_UNHEALTHY pod={POD_NAME}\n")
            else:
                self._write(200, f"healthy pod={POD_NAME}\n")
            return

        if self.path == "/ready":
            if os.path.exists(READINESS_FLAG):
                self._write(500, f"NOT_READY pod={POD_NAME}\n")
            else:
                self._write(200, f"ready pod={POD_NAME}\n")
            return

        if self.path == "/version":
            self._write(200, f"{APP_VERSION}\n")
            return

        self._write(200, f"Hello from pod={POD_NAME} version={APP_VERSION} time={time.time():.3f}\n")

    def log_message(self, fmt, *args):
        print(f"[app:{POD_NAME}] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"[app] starting pod={POD_NAME} version={APP_VERSION}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
