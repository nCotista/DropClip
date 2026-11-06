"""Small-body contract checks for the streaming S0.2 receiver."""
import hashlib
import io
import unittest
from unittest.mock import patch

import receiver


class ReceiverTests(unittest.TestCase):
    def run_request(self, path, length, body):
        handler = receiver.Receiver.__new__(receiver.Receiver)
        handler.path = path
        handler.headers = {"Content-Length": length}
        handler.rfile = io.BytesIO(body)
        handler.wfile = io.BytesIO()
        handler.send_response = lambda status: setattr(handler, "status", status)
        handler.send_error = lambda status, message: setattr(handler, "status", status)
        handler.end_headers = lambda: None
        with patch.object(receiver, "SIZE", 5), patch.object(receiver, "CHUNK", bytes(2)), \
             patch.object(receiver, "EXPECTED", hashlib.sha256(bytes(5))):
            handler.do_POST()
        return handler.status, handler.wfile.getvalue()

    def test_valid_body(self):
        self.assertEqual(self.run_request("/upload", "5", bytes(5)), (200, b"verified"))

    def test_wrong_path(self):
        self.assertEqual(self.run_request("/other", "5", bytes(5))[0], 400)

    def test_wrong_length(self):
        self.assertEqual(self.run_request("/upload", "4", bytes(5))[0], 400)

    def test_corrupt_body(self):
        self.assertEqual(self.run_request("/upload", "5", b"hello")[0], 422)

    def test_truncated_body(self):
        self.assertEqual(self.run_request("/upload", "5", bytes(4))[0], 422)


if __name__ == "__main__":
    unittest.main()
