#!/usr/bin/env python3
"""HTTP server with Range request support for video scrubbing."""
import http.server
import os, sys, mimetypes

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 7788
ROOT = os.path.dirname(os.path.abspath(__file__))

class RangeHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # suppress logs

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/': path = '/index.html'
        file_path = os.path.join(ROOT, path.lstrip('/'))
        if not os.path.isfile(file_path):
            self.send_error(404); return

        size = os.path.getsize(file_path)
        mime, _ = mimetypes.guess_type(file_path)
        mime = mime or 'application/octet-stream'

        # Parse Range header
        range_header = self.headers.get('Range')
        start, end = 0, size - 1
        status = 200

        if range_header:
            try:
                r = range_header.replace('bytes=', '').split('-')
                start = int(r[0]) if r[0] else 0
                end   = int(r[1]) if r[1] else size - 1
                end   = min(end, size - 1)
                status = 206
            except Exception:
                self.send_error(416); return

        length = end - start + 1
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(length))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Access-Control-Allow-Origin', '*')
        if status == 206:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()

        with open(file_path, 'rb') as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk: break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def do_HEAD(self):
        path = self.path.split('?')[0]
        if path == '/': path = '/index.html'
        file_path = os.path.join(ROOT, path.lstrip('/'))
        if not os.path.isfile(file_path):
            self.send_error(404); return
        size = os.path.getsize(file_path)
        mime, _ = mimetypes.guess_type(file_path)
        self.send_response(200)
        self.send_header('Content-Type', mime or 'application/octet-stream')
        self.send_header('Content-Length', str(size))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()

if __name__ == '__main__':
    server = http.server.HTTPServer(('', PORT), RangeHandler)
    print(f'Serving {ROOT} on http://localhost:{PORT}')
    server.serve_forever()
