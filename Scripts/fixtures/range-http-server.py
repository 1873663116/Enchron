#!/usr/bin/env python3

import argparse
import base64
import json
import os
import re
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class RangeRequestHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        super().setup()
        self.connection_id = self.server.open_connection(self.client_address)

    def finish(self):
        try:
            super().finish()
        finally:
            self.server.close_connection(self.connection_id)

    def send_head(self):
        expected = "Basic " + base64.b64encode(
            f"{self.server.username}:{self.server.password}".encode()
        ).decode()
        if self.headers.get("Authorization") != expected:
            self.server.record_request(
                self.connection_id,
                self.command,
                self.path,
                self.headers.get("Range"),
                401,
                0,
            )
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Enchron Verification"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None

        path = self.translate_path(self.path)
        if os.path.isdir(path):
            self.send_error(404)
            return None
        try:
            source = open(path, "rb")
        except OSError:
            self.server.record_request(
                self.connection_id,
                self.command,
                self.path,
                self.headers.get("Range"),
                404,
                0,
            )
            self.send_error(404)
            return None

        size = os.fstat(source.fileno()).st_size
        start = 0
        end = size - 1
        status = 200
        requested_range = self.headers.get("Range")
        if requested_range:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested_range.strip())
            if not match:
                source.close()
                self.server.record_request(
                    self.connection_id,
                    self.command,
                    self.path,
                    requested_range,
                    416,
                    0,
                )
                self.send_error(416)
                return None
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), end) if last else end
            elif last:
                start = max(size - int(last), 0)
            if start >= size or start > end:
                source.close()
                self.server.record_request(
                    self.connection_id,
                    self.command,
                    self.path,
                    requested_range,
                    416,
                    0,
                )
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return None
            status = 206

        self._range = (start, end)
        self.send_response(status)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Last-Modified", self.date_time_string(os.fstat(source.fileno()).st_mtime))
        self.end_headers()
        self.server.record_request(
            self.connection_id,
            self.command,
            self.path,
            requested_range,
            status,
            end - start + 1,
        )
        return source

    def copyfile(self, source, outputfile):
        start, end = self._range
        source.seek(start)
        remaining = end - start + 1
        while remaining:
            chunk = source.read(min(256 * 1024, remaining))
            if not chunk:
                break
            try:
                outputfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                break
            remaining -= len(chunk)


class RecordingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler, username, password, log_file):
        super().__init__(address, handler)
        self.username = username
        self.password = password
        self.log_file = log_file
        self.log_lock = threading.Lock()
        self.connection_sequence = 0

    def record(self, event, **fields):
        entry = {"event": event, "monotonic_ns": time.monotonic_ns(), **fields}
        with self.log_lock:
            with open(self.log_file, "a", encoding="utf-8") as output:
                output.write(json.dumps(entry, separators=(",", ":")) + "\n")

    def open_connection(self, client_address):
        with self.log_lock:
            self.connection_sequence += 1
            connection_id = self.connection_sequence
        self.record(
            "connection_open",
            connection_id=connection_id,
            client_host=client_address[0],
            client_port=client_address[1],
        )
        return connection_id

    def close_connection(self, connection_id):
        self.record("connection_close", connection_id=connection_id)

    def record_request(
        self,
        connection_id,
        method,
        path,
        requested_range,
        status,
        response_bytes,
    ):
        self.record(
            "request",
            connection_id=connection_id,
            method=method,
            path=path,
            range=requested_range,
            status=status,
            response_bytes=response_bytes,
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--log-file")
    parser.add_argument("--ready-file")
    arguments = parser.parse_args()

    handler = lambda *args, **kwargs: RangeRequestHandler(
        *args, directory=arguments.directory, **kwargs
    )
    log_file = arguments.log_file or os.devnull
    server = RecordingHTTPServer(
        ("127.0.0.1", arguments.port),
        handler,
        arguments.username,
        arguments.password,
        log_file,
    )
    if arguments.ready_file:
        with open(arguments.ready_file, "w", encoding="utf-8") as output:
            output.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
