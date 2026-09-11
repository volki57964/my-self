#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""CI-only test server. Not included or contacted by the installed application."""
import http.server, socketserver, ssl, sys, threading, time
class TCP(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(10)
        try:
            while True:
                data=self.request.recv(4096)
                if not data:return
                self.request.sendall(data)
        except (OSError,TimeoutError):pass
class UDP(socketserver.BaseRequestHandler):
    def handle(self):self.request[1].sendto(self.request[0],self.client_address)
class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'<html><title>NetCheck test</title>NetCheck test OK.</html>'
        self.send_response(200);self.send_header('Content-Type','text/html');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
class TCPS(socketserver.ThreadingTCPServer):allow_reuse_address=True;daemon_threads=True
class UDPS(socketserver.ThreadingUDPServer):allow_reuse_address=True;daemon_threads=True
servers=[TCPS(('127.0.0.1',18443),TCP),UDPS(('127.0.0.1',18444),UDP),http.server.ThreadingHTTPServer(('127.0.0.1',80),HTTP)]
secure=http.server.ThreadingHTTPServer(('127.0.0.1',443),HTTP)
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(sys.argv[1],sys.argv[2]);secure.socket=ctx.wrap_socket(secure.socket,server_side=True);servers.append(secure)
for s in servers:threading.Thread(target=s.serve_forever,daemon=True).start()
print('NETCHECK_LOOPBACK_READY',flush=True)
while True:time.sleep(60)
