from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', 'https://example.test/not-followed')
            self.end_headers()
            return
        self.send_response(500 if self.path == '/error' else 200)
        self.send_header('Content-Type', 'application/json')
        data = b'x' * 4096 if self.path in ('/large', '/stream') else b'{}'
        if self.path != '/stream':
            self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port), encoding='utf-8')
server.serve_forever()
