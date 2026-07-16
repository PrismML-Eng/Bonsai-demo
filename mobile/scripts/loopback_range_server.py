#!/usr/bin/env python3
"""Deterministic loopback-only HTTP fixture for resumable download integration tests."""

from __future__ import annotations

import argparse
import http.server
import json
import socket
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True, type=Path)
    parser.add_argument("--port-file", required=True, type=Path)
    parser.add_argument("--log-file", required=True, type=Path)
    args = parser.parse_args()
    payload = args.payload.read_bytes()

    class Handler(http.server.BaseHTTPRequestHandler):
        interrupted = False

        def do_GET(self) -> None:  # noqa: N802 - HTTP handler API
            range_header = self.headers.get("Range")
            with args.log_file.open("a", encoding="utf-8") as log:
                log.write(json.dumps({"path": self.path, "range": range_header}) + "\n")

            if self.path == "/model" and not range_header and not Handler.interrupted:
                Handler.interrupted = True
                cut = max(1, len(payload) // 3)
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload[:cut])
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return

            if self.path == "/model" and range_header:
                start = int(range_header.removeprefix("bytes=").split("-", 1)[0])
                body = payload[start:]
                self.send_response(206)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Content-Range", f"bytes {start}-{len(payload) - 1}/{len(payload)}")
                self.end_headers()
                self.wfile.write(body)
                return

            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    args.port_file.write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
