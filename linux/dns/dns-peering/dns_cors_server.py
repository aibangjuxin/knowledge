#!/usr/bin/env python3
import http.server
import socketserver
import urllib.parse
import subprocess
import json
import os
import sys

# Configuration
PORT = 8000
SCRIPT_PATH = "./verify-pub-priv-ip-glm-ipv6.sh"

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'X-Requested-With, Content-Type')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        # Parse URL
        parsed_path = urllib.parse.urlparse(self.path)
        
        # API Endpoint: /api/check?domain=example.com
        if parsed_path.path == '/api/check':
            self.handle_api_check(parsed_path.query)
        else:
            # Serve static files (optional, but good for testing)
            super().do_GET()

    def handle_api_check(self, query_string):
        params = urllib.parse.parse_qs(query_string)
        domain_list = params.get('domain', [])
        
        if not domain_list:
            self.send_error_response(400, "Missing 'domain' parameter")
            return

        domain = domain_list[0]
        
        if not self.is_valid_domain(domain):
            self.send_error_response(400, "Invalid domain format")
            return

        try:
            # Execute the shell script
            cmd = [SCRIPT_PATH, domain, "--output", "json"]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=15 
            )
            
            if not result.stdout.strip():
                 if result.stderr:
                     print(f"Script Error: {result.stderr}", file=sys.stderr)
                     self.send_error_response(500, "Script execution failed")
                     return

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(result.stdout.encode('utf-8'))

        except subprocess.TimeoutExpired:
            self.send_error_response(504, "Script evaluation timed out")
        except Exception as e:
            print(f"Internal Error: {e}", file=sys.stderr)
            self.send_error_response(500, str(e))

    def send_error_response(self, code, message):
        self.send_response(code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = json.dumps({"error": message, "status": "failed"})
        self.wfile.write(response.encode('utf-8'))

    def is_valid_domain(self, domain):
        allowed_chars = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:")
        return all(c in allowed_chars for c in domain) and not domain.startswith('-')

if __name__ == "__main__":
    if not os.path.exists(SCRIPT_PATH):
        print(f"Error: Script not found at {SCRIPT_PATH}")
        sys.exit(1)

    if not os.access(SCRIPT_PATH, os.X_OK):
        try:
            os.chmod(SCRIPT_PATH, 0o755)
        except Exception as e:
            print(f"Error making script executable: {e}")
            sys.exit(1)

    print(f"Starting CORS DNS Server on port {PORT}...")
    print(f"Backend Ready. Configure your GitHub Page to point to: http://localhost:{PORT}")
    
    with socketserver.TCPServer(("", PORT), CORSRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopping server...")
