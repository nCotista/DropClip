"""S0.2 LAN-only TLS 1.3 receiver; validates a 4 GiB zero-filled test file."""
import hashlib
import ipaddress
import getpass
import ssl
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SIZE = 4 * 1024 * 1024 * 1024
CHUNK = bytes(1024 * 1024)
EXPECTED = hashlib.sha256()
for _ in range(SIZE // len(CHUNK)):
    EXPECTED.update(CHUNK)


class Receiver(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/upload" or self.headers.get("Content-Length") != str(SIZE):
            self.send_error(400, "Expected /upload with a 4 GiB body")
            return
        remaining = SIZE
        digest = hashlib.sha256()
        while remaining:
            data = self.rfile.read(min(len(CHUNK), remaining))
            if not data:
                break
            digest.update(data)
            remaining -= len(data)
        valid = remaining == 0 and digest.digest() == EXPECTED.digest()
        self.send_response(200 if valid else 422)
        self.end_headers()
        self.wfile.write(b"verified" if valid else b"mismatch")
        print(f"received={SIZE - remaining} sha256={digest.hexdigest()} valid={valid}", flush=True)


if __name__ == "__main__":
    _, bind_ip, cert_path, key_path = sys.argv
    address = ipaddress.ip_address(bind_ip)
    if not (address.is_private or address.is_link_local or address.is_loopback):
        raise ValueError("Bind to a local address only")
    server = HTTPServer((bind_ip, 53317), Receiver)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(cert_path, key_path, password=getpass.getpass("Encrypted key password: "))
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
