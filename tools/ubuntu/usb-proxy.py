#!/usr/bin/env python3
"""A small HTTP proxy for the phone, so apt in the Ubuntu chroot reaches the
internet through this PC without NAT or root: plain HTTP requests (apt with
http:// mirrors) and CONNECT tunnels (https). It listens only on the USB
network address, 172.16.42.2:3128 by default.

usage: usb-proxy.py [address] [port]
"""
import select
import socket
import socketserver
import sys
from urllib.parse import urlsplit


def pipe(a, b):
    socks = [a, b]
    while True:
        r, _, x = select.select(socks, [], socks, 120)
        if x or not r:
            return
        for s in r:
            data = s.recv(65536)
            if not data:
                return
            (b if s is a else a).sendall(data)


class Proxy(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline(65536).decode('latin-1')
        if not line:
            return
        method, target, version = line.split()
        headers = []
        while True:
            h = self.rfile.readline(65536)
            if h in (b'\r\n', b'\n', b''):
                break
            headers.append(h)

        if method == 'CONNECT':
            host, _, port = target.rpartition(':')
            try:
                up = socket.create_connection((host, int(port)), timeout=30)
            except OSError as e:
                self.wfile.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
                print('CONNECT', target, 'failed:', e, flush=True)
                return
            self.wfile.write(b'HTTP/1.1 200 Connection established\r\n\r\n')
            print('CONNECT', target, flush=True)
            pipe(self.connection, up)
            up.close()
            return

        u = urlsplit(target)
        path = (u.path or '/') + ('?' + u.query if u.query else '')
        try:
            up = socket.create_connection((u.hostname, u.port or 80), timeout=30)
        except OSError as e:
            self.wfile.write(b'HTTP/1.1 502 Bad Gateway\r\n\r\n')
            print(method, target, 'failed:', e, flush=True)
            return
        print(method, target, flush=True)
        req = f'{method} {path} {version}\r\n'.encode('latin-1')
        # one request per connection keeps this simple
        kept = [h for h in headers
                if not h.lower().startswith((b'proxy-connection', b'connection'))]
        up.sendall(req + b''.join(kept) + b'Connection: close\r\n\r\n')
        pipe(self.connection, up)
        up.close()


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


addr = sys.argv[1] if len(sys.argv) > 1 else '172.16.42.2'
port = int(sys.argv[2]) if len(sys.argv) > 2 else 3128
print(f'proxy on {addr}:{port}', flush=True)
Server((addr, port), Proxy).serve_forever()
