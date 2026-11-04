#!/usr/bin/env python3
"""Generated-only LAN fixture. No access to local files; Ctrl-C to stop."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
import argparse
import struct
import zlib

PAGE = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LAN Browser checks</title><style>body{font:18px system-ui;padding:20px}li{margin:20px 0}button{font:inherit}</style>
<h1>LAN Browser checks</h1><ul>
<li><a href="/login">Password saving (use made-up credentials)</a></li>
<li><a href="/next">Navigation page</a></li>
<li><a href="/next" target="_blank">New window (opens a new tab)</a></li>
<li><a href="/redirect">HTTP redirect</a></li>
<li><a href="/https">Redirect to HTTPS example.com (internet required)</a></li>
<li><a href="/download">Attachment download (repeat for same filename)</a></li>
<li><a href="/attachment-html">HTML attachment (should save, not render)</a></li>
<li><a href="/slow">Slow download</a></li>
<li><a href="/broken">Interrupted download (failure expected)</a></li>
<li><a href="/text" download="link-download.txt">HTML download attribute</a></li>
<li><button onclick="const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['Blob download works.'],{type:'text/plain'}));a.download='blob-test.txt';a.click();">Blob download</button></li>
<li><button onclick="alert('Alert works')">Alert</button></li>
<li><button onclick="this.textContent=confirm('Confirm works?')?'Confirmed':'Cancelled'">Confirm</button></li>
<li><button onclick="this.textContent=prompt('Type something','Hello')??'Cancelled'">Prompt</button></li></ul>'''


def png_chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))


ICON = (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('!2I5B', 32, 32, 8, 2, 0, 0, 0))
        + png_chunk(b'IDAT', zlib.compress(b''.join(b'\0' + bytes((220, 170, 40)) * 32 for _ in range(32))))
        + png_chunk(b'IEND', b''))


class Handler(BaseHTTPRequestHandler):
    def icon_response(self):
        route = self.path.split('?', 1)[0]
        if route in ('/icons/missing', '/icons/malformed', '/icons/oversized', '/icons/redirect', '/icons/external', '/icons/delayed', '/icons/relative', '/icons/chunked'):
            links = {
                '/icons/missing': 'missing.png',
                '/icons/malformed': 'malformed.png',
                '/icons/oversized': 'oversized.png',
                '/icons/redirect': 'redirect.png',
                '/icons/external': 'http://localhost:1/must-not-be-requested.png',
                '/icons/delayed': 'delayed.png',
                '/icons/relative': './assets/icon.png',
                '/icons/chunked': 'chunked.png',
            }
            data = ('<title>Icon fixture</title><link rel="shortcut icon" href="' + links[route] + '">').encode()
            content_type = 'text/html'
        elif route == '/icons/fallback':
            data, content_type = b'<title>Root favicon fixture</title>', 'text/html'
        elif route == '/icons/redirect.png':
            self.send_response(302)
            self.send_header('Location', '/icons/assets/icon.png')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        elif route == '/icons/malformed.png':
            data, content_type = b'not an image', 'image/png'
        elif route == '/icons/oversized.png':
            data, content_type = b'x' * (512 * 1024 + 1), 'image/png'
        elif route == '/icons/delayed.png':
            time.sleep(2)
            data, content_type = ICON, 'image/png'
        elif route == '/icons/chunked.png':
            self.protocol_version = 'HTTP/1.1'
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            for offset in range(0, len(ICON), 13):
                piece = ICON[offset:offset + 13]
                self.wfile.write(('%x\r\n' % len(piece)).encode() + piece + b'\r\n')
            self.wfile.write(b'0\r\n\r\n')
            return
        elif route == '/icons/assets/icon.png' or (route == '/favicon.ico' and self.server.fallback_icon):
            data, content_type = ICON, 'image/png'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        if self.path != '/login':
            self.send_error(404)
            return
        # Discard the body without logging or echoing credentials.
        length = int(self.headers.get('Content-Length', '0'))
        if length > 65536:
            self.send_error(413)
            return
        self.rfile.read(length)
        self.send_response(303)
        self.send_header('Location', '/login')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        if self.path.startswith('/icons/') or self.path == '/favicon.ico':
            self.icon_response()
            return
        route = self.path.split('?', 1)[0]
        if route in ('/redirect', '/https'):
            self.send_response(302)
            self.send_header('Location', '/next' if route == '/redirect' else 'https://example.com/')
            self.end_headers()
            return
        if route in ('/download', '/slow', '/broken', '/text', '/attachment-html'):
            data = b'LAN Browser download works.\n'
            content_type = 'text/plain'
            if route == '/attachment-html':
                data = b'<html><body>Saved HTML attachment.</body></html>'
                content_type = 'text/html'
            if route in ('/slow', '/broken'):
                data *= 20000
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            if route != '/text':
                filename = 'test.html' if route == '/attachment-html' else 'lan-browser-test.txt'
                self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.end_headers()
            if route == '/broken':
                self.wfile.write(data[:100])
                self.wfile.flush()
                self.close_connection = True
                return
            try:
                for offset in range(0, len(data), 4096):
                    self.wfile.write(data[offset:offset + 4096])
                    self.wfile.flush()
                    if route == '/slow':
                        time.sleep(0.08)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if route == '/':
            data = PAGE
        elif route == '/login':
            data = b'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Password saving checks</title><h1>Password saving checks</h1>
<p>Use made-up credentials. This fixture discards the submitted values.</p>
<form method="post" action="/login"><label>Username <input name="username" autocomplete="username"></label>
<label>Password <input type="password" name="password" autocomplete="current-password"></label>
<button>Sign In</button></form>'''
        elif route == '/next':
            data = b'<meta name="viewport" content="width=device-width"><title>Next page</title><h1>Navigation works</h1><a href="/">Back to checks</a>'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8889)
    parser.add_argument('--fallback-icon', action='store_true')
    args = parser.parse_args()
    print(f'Open http://YOUR_MAC_LAN_IP:{args.port}/ on the phone. Ctrl-C to stop.', flush=True)
    try:
        server = ThreadingHTTPServer(('0.0.0.0', args.port), Handler)
        server.fallback_icon = args.fallback_icon
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopped.')
