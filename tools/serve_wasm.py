#!/usr/bin/env python3
"""Simple HTTP server with COOP/COEP headers for Flutter WASM builds."""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8082
DIR = sys.argv[2] if len(sys.argv) > 2 else '.'

class WasmHandler(http.server.SimpleHTTPRequestHandler):
    # 注册正确的 MIME 类型
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.mjs': 'application/javascript',
        '.wasm': 'application/wasm',
        '.js': 'application/javascript',
        '.css': 'text/css',
    }

    def end_headers(self):
        # Required for SharedArrayBuffer / WASM threads
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_error(self, format, *args):
        # Silently ignore 404s for devtools probes (.well-known, .map, etc.)
        if args and args[0] == 404:
            return
        super().log_error(format, *args)

    def log_message(self, format, *args):
        try:
            print(f'[{self.log_date_time_string()}] {args[0]} {args[1]} {args[2]}')
        except IndexError:
            pass  # suppress malformed log messages

os.chdir(DIR)
server = http.server.HTTPServer(('0.0.0.0', PORT), WasmHandler)
print(f'Serving {DIR} at http://localhost:{PORT} (with COOP/COEP headers)')
server.serve_forever()
