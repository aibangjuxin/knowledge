"""
Canonical Python stdlib HTTPS server for PSC NEG backend MIGs.

Serves:
  - HTTP 80  /healthz  → 200 'ok'        (GCP LB HTTP health check path)
  - HTTP 80  /         → 200 index.html  (LB round-robin / debugging)
  - HTTPS 443 /         → 200 index.html  (real cert+key, terminates TLS)
  - HTTPS 443 /healthz  → 200 'ok'

This avoids the "no-address VM cannot apt-get install nginx" problem:
- no Cloud NAT needed
- no nginx/apache required
- works on plain debian-11 base image (Python 3.11 stdlib only)

CRITICAL Debian 11 / Python 3.11 gotcha:
  from http.server import ThreadingMixIn   ← AttributeError (does not exist)
  from socketserver import ThreadingMixIn  ← correct path
  http.server.HTTPServer + socketserver.ThreadingMixIn  ← the working class

Place at /opt/tenant/server.py on the MIG VM. Run under systemd (see
templates/same-project-psc-test-setup/tenant-server.service). cert+key
should be placed at /opt/tenant/server.crt and /opt/tenant/server.key
by the instance-template startup-script via base64 heredoc.
"""

import http.server
import os
import socket
import ssl
import socketserver
import sys
import threading
import time

CERT = "/opt/tenant/server.crt"
KEY = "/opt/tenant/server.key"

INDEX_HTML = """<!DOCTYPE html>
<html>
<head><title>tenant.taobao.abjx.uk</title></head>
<body>
<h1>OK</h1>
<p>Hello from PSC NEG end-to-end test (HTTPS)</p>
<p>VM: {hostname}</p>
<p>Time: {time}</p>
</body>
</html>
"""


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
            return

        body = INDEX_HTML.format(
            hostname=socket.gethostname(),
            time=time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def serve_http():
    srv = ThreadedHTTPServer(("0.0.0.0", 80), H)
    sys.stderr.write("[http] listening on :80\n")
    srv.serve_forever()


def serve_https():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    srv = ThreadedHTTPServer(("0.0.0.0", 443), H)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("[https] listening on :443\n")
    srv.serve_forever()


def main():
    # Sanity: verify cert+key modulus match at startup
    import subprocess

    def mod(path):
        out = subprocess.run(
            ["openssl", "x509" if path.endswith(".crt") else "rsa",
             "-in", path, "-noout", "-modulus"],
            capture_output=True, text=True, check=False,
        )
        return out.stdout.replace("Modulus=", "").strip() if out.returncode == 0 else ""

    if mod(CERT) and mod(KEY) and mod(CERT) == mod(KEY):
        sys.stderr.write("[startup] OK cert+key modulus matched\n")
    else:
        sys.stderr.write("[startup] FAIL cert+key NOT matched — TLS will fail\n")
        sys.exit(1)

    # Daemon thread for HTTP 80 (health check)
    threading.Thread(target=serve_http, daemon=True).start()
    # Main thread: HTTPS 443
    serve_https()


if __name__ == "__main__":
    main()
