#!/usr/bin/env python3
"""
Simple Python web application for SLSA security demonstration
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import os

PORT = int(os.environ.get('PORT', 8080))

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Hello from secure CI/CD with SLSA + Cosign (Python Edition)!\n')

    def log_message(self, format, *args):
        # Print logs to stdout for container logging
        print(f"{self.address_string()} - {format % args}")

def run_server():
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, SimpleHandler)
    print(f'Starting Python web server on port {PORT}...')
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
