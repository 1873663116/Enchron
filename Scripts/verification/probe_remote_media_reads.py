#!/usr/bin/env python3
"""Measure what a remote MP4 costs to open, without going through the app.

Measurements taken through PlaybackCore cannot separate three things: how many
bytes `avformat_find_stream_info` really consumes, whether 1-2 MB/s is the
server's ceiling or an artifact of one-connection-per-seek reads, and whether an
open-ended `bytes=0-` triggers the same server defect that made
`http_source_length` necessary. Each subcommand isolates one of them by talking
to the server directly.

`ffprobe` runs behind a loopback proxy rather than embedding credentials in the
URL, because ffprobe takes its input only from argv. The proxy earns its place
twice over: it also records every Range header and every TCP connection, which
is what the local experiments in
docs/research/remote-media-probing-practice-2026-08-15.md had and a direct
ffprobe run does not.

Credentials come from WEBDAV_USER / WEBDAV_PASSWORD and EMBY_USER /
EMBY_PASSWORD, so `set -a; . .env; set +a` covers it and nothing lands in argv.

Usage:
    set -a; . .env; set +a
    probe_remote_media_reads.py boxes
    probe_remote_media_reads.py throughput
    probe_remote_media_reads.py openended
    probe_remote_media_reads.py ffprobe [--end-offset] [--extra ARG ...]
"""

import argparse
import base64
import hashlib
import http.client
import http.server
import json
import os
import re
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

def _default_webdav_host() -> str:
    try:
        import sys as _sys
        from pathlib import Path as _Path
        import json as _json
        _sys.path.insert(0, str(_Path(__file__).resolve().parent))
        import ensure_test_services as _ets
        receipt = _ets._read_object(_ets.webdav_spec().receipt_file)
        if isinstance(receipt, dict) and isinstance(receipt.get("address"), str) and receipt.get("address"):
            host = _ets.endpoint_host(str(receipt["address"]))
            if host:
                return host
        spec = _ets.webdav_spec()
        if spec.recorded_address:
            host = _ets.endpoint_host(spec.recorded_address)
            if host:
                return host
    except Exception:
        pass
    return "Mac-mini.local"
def _default_emby_address() -> str:
    try:
        import sys as _sys2
        from pathlib import Path as _Path2
        import json as _json2
        _sys2.path.insert(0, str(_Path2(__file__).resolve().parent))
        import ensure_test_services as _ets2
        receipt = _ets2._read_object(_ets2.emby_spec().receipt_file)
        if isinstance(receipt, dict) and isinstance(receipt.get("address"), str) and receipt.get("address"):
            return str(receipt["address"])
        spec = _ets2.emby_spec()
        if spec.recorded_address:
            return spec.recorded_address
    except Exception:
        pass
    try:
        from pathlib import Path as _Path3
        import json as _json3
        p = _Path3(__file__).resolve().parents[2] / "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
        if p.is_file():
            d = _json3.loads(p.read_text(encoding="utf-8"))
            if isinstance(d.get("address"), str) and d.get("address"):
                return str(d["address"])
    except Exception:
        pass
    return "http://Mac-mini.local:8096"
WEBDAV_HOST = _default_webdav_host()
WEBDAV_PORT = 5244
WEBDAV_PATH = "/dav/夸克/影音库/电影/Blade Runner 2049 (2017)/Blade Runner 2049 (2017).mp4"
EMBY_ADDRESS = _default_emby_address()
EMBY_ITEM_NAME = "Blade Runner 2049"

CLIENT = "Enchron"
DEVICE = "EnchronProbe"
DEVICE_ID = "enchron-remote-read-probe"
VERSION = "1.0"


def webdav_target():
    user = os.environ.get("WEBDAV_USER")
    password = os.environ.get("WEBDAV_PASSWORD")
    if not user or not password:
        sys.exit("set WEBDAV_USER and WEBDAV_PASSWORD (set -a; . .env; set +a)")
    quoted = urllib.parse.quote(WEBDAV_PATH)
    header = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
    return f"http://{WEBDAV_HOST}:{WEBDAV_PORT}{quoted}", header


def ranged(url, header, start, end=None, read_limit=None, timeout=120):
    """One ranged GET. `end` None means the open-ended `bytes=N-` form."""
    request = urllib.request.Request(url)
    request.add_header("Authorization", header)
    request.add_header("Range", f"bytes={start}-" if end is None else f"bytes={start}-{end}")
    started = time.time()
    try:
        response = urllib.request.urlopen(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        return {"status": error.code, "error": error.reason, "headers": dict(error.headers)}
    with response:
        first_byte = time.time() - started
        want = read_limit if read_limit is not None else None
        chunks, total = [], 0
        while True:
            block = response.read(65536 if want is None else min(65536, want - total))
            if not block:
                break
            chunks.append(block)
            total += len(block)
            if want is not None and total >= want:
                break
        body = b"".join(chunks)
    return {
        "status": response.status,
        "content_range": response.headers.get("Content-Range"),
        "content_length": response.headers.get("Content-Length"),
        "connection": response.headers.get("Connection"),
        "first_byte_s": first_byte,
        "elapsed_s": time.time() - started,
        "bytes": total,
        "sha256": hashlib.sha256(body).hexdigest(),
        "leading_zero_run": len(body) - len(body.lstrip(b"\0")),
        "trailing_zero_run": len(body) - len(body.rstrip(b"\0")),
    }


def file_size(url, header):
    request = urllib.request.Request(url, method="HEAD")
    request.add_header("Authorization", header)
    with urllib.request.urlopen(request, timeout=60) as response:
        return int(response.headers["Content-Length"])


def read_range(url, header, start, length):
    request = urllib.request.Request(url)
    if header:
        request.add_header("Authorization", header)
    request.add_header("Range", f"bytes={start}-{start+length-1}")
    started = time.time()
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read(), time.time() - started


def cmd_boxes(args):
    url, header = webdav_target()
    total = file_size(url, header)
    print(f"file size {total}")
    offset, walked, fragmented = 0, 0, False
    while offset < total and walked < 200:
        head, elapsed = read_range(url, header, offset, 32)
        if len(head) < 8:
            print(f"short read {len(head)} at {offset}")
            break
        size = struct.unpack(">I", head[0:4])[0]
        kind = head[4:8].decode("latin1")
        if size == 1:
            size = struct.unpack(">Q", head[8:16])[0]
        elif size == 0:
            size = total - offset
        if kind in ("moof", "sidx", "styp"):
            fragmented = True
        print(f"{offset:>14}  {kind}  size={size}  ({elapsed*1000:.0f} ms)")
        offset += size
        walked += 1
    print(f"walked {walked} top-level boxes, ended at {offset} of {total}")
    print(f"fragmented MP4: {fragmented}")


def cmd_throughput(args):
    url, header = webdav_target()
    total = file_size(url, header)
    window = args.window
    moov_start = total - 7360986
    spots = [
        ("head", 0),
        ("mid", total // 2),
        ("moov head", moov_start),
        ("tail-window", total - window),
    ]
    print(f"single sequential connection, explicit end, {window/2**20:.0f} MiB per spot\n")
    for label, start in spots:
        end = min(start + window, total) - 1
        result = ranged(url, header, start, end)
        rate = result["bytes"] / result["elapsed_s"] / 2**20
        print(f"  {label:<12} offset {start:>14}  {result['bytes']/2**20:6.1f} MiB  "
              f"ttfb {result['first_byte_s']*1000:6.0f} ms  {result['elapsed_s']:6.2f} s  {rate:6.2f} MiB/s")

    print(f"\nmany small ranged requests, {args.chunk/1024:.0f} KiB each, "
          f"new connection each, mimicking one-connection-per-seek")
    started = time.time()
    moved = 0
    for index in range(args.chunks):
        start = index * args.chunk
        result = ranged(url, header, start, start + args.chunk - 1)
        moved += result["bytes"]
    elapsed = time.time() - started
    print(f"  {args.chunks} requests  {moved/2**20:.1f} MiB  {elapsed:.2f} s  "
          f"{moved/elapsed/2**20:.2f} MiB/s  ({elapsed/args.chunks*1000:.0f} ms per request)")

    print(f"\nopen-ended bytes=N- read then abandoned after {window/2**20:.0f} MiB")
    for label, start in (("head", 0), ("moov head", moov_start)):
        result = ranged(url, header, start, None, read_limit=window)
        rate = result["bytes"] / result["elapsed_s"] / 2**20
        print(f"  {label:<12} offset {start:>14}  {result['bytes']/2**20:6.1f} MiB  "
              f"ttfb {result['first_byte_s']*1000:6.0f} ms  {result['elapsed_s']:6.2f} s  {rate:6.2f} MiB/s")


def emby_request(path, token=None, method="GET", body=None, query=None):
    url = EMBY_ADDRESS + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    fields = [f'Client="{CLIENT}"', f'Device="{DEVICE}"', f'DeviceId="{DEVICE_ID}"', f'Version="{VERSION}"']
    if token:
        fields.append(f'Token="{token}"')
    request.add_header("X-Emby-Authorization", "MediaBrowser " + ", ".join(fields))
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    started = time.time()
    with urllib.request.urlopen(request, timeout=600) as response:
        payload = response.read()
    return (json.loads(payload) if payload else {}), time.time() - started


def emby_session():
    user = os.environ.get("EMBY_USER")
    password = os.environ.get("EMBY_PASSWORD")
    if not user or not password:
        sys.exit("set EMBY_USER and EMBY_PASSWORD (set -a; . .env; set +a)")
    result, _ = emby_request("/Users/AuthenticateByName", method="POST",
                             body={"Username": user, "Pw": password})
    return result["AccessToken"], result["User"]["Id"]


def emby_stream_url(token, user_id, name=EMBY_ITEM_NAME):
    result, _ = emby_request(f"/Users/{user_id}/Items", token=token, query={
        "Recursive": "true", "IncludeItemTypes": "Movie",
        "SearchTerm": name, "Fields": "MediaSources,Path", "Limit": "5",
    })
    items = result.get("Items") or []
    if not items:
        sys.exit(f"Emby returned no Movie matching {name!r}")
    item = items[0]
    source = (item.get("MediaSources") or [{}])[0]
    query = urllib.parse.urlencode({
        "Static": "true", "MediaSourceId": source.get("Id"), "api_key": token,
    })
    container = source.get("Container") or "mp4"
    url = f"{EMBY_ADDRESS}/Videos/{item['Id']}/stream.{container}?{query}"
    return item, source, url


def report(label, result, reference=None):
    if "error" in result:
        print(f"  {label:<34} HTTP {result['status']}  {result['error']}")
        return
    verdict = ""
    if reference is not None:
        same = result["sha256"] == reference["sha256"] and result["bytes"] == reference["bytes"]
        verdict = "  MATCH" if same else "  DIFFERS"
    print(f"  {label:<34} HTTP {result['status']}  got {result['bytes']} B  "
          f"Content-Range {result['content_range']}  Content-Length {result['content_length']}"
          f"{verdict}")
    if result["leading_zero_run"] or result["trailing_zero_run"]:
        print(f"  {'':<34} zero run: {result['leading_zero_run']} leading, "
              f"{result['trailing_zero_run']} trailing")


def check_open_ended(label, url, header, total, probe_bytes):
    print(f"\n=== {label} ===")
    print(f"  advertised length {total}")

    print("\n  start at 0")
    closed = ranged(url, header, 0, probe_bytes - 1)
    report("bytes=0-%d (control)" % (probe_bytes - 1), closed)
    opened = ranged(url, header, 0, None, read_limit=probe_bytes)
    report("bytes=0- (read %d then close)" % probe_bytes, opened, reference=closed)
    if not ("error" in opened or "error" in closed):
        advertised = opened["content_length"]
        expected = str(total)
        print(f"  {'':<34} open-ended Content-Length {advertised}, "
              f"file length {expected}, {'agrees' if advertised == expected else 'DISAGREES'}")

    print("\n  short read near the tail (the case known to be answered wrong)")
    for back in (probe_bytes, 65536, 4096):
        start = total - back
        closed = ranged(url, header, start, total - 1)
        report(f"bytes={start}-{total-1} (control)", closed)
        opened = ranged(url, header, start, None)
        report(f"bytes={start}- (open-ended)", opened, reference=closed)

    print("\n  short read in the middle")
    start = total // 2
    closed = ranged(url, header, start, start + 65535)
    report(f"bytes={start}-{start+65535} (control)", closed)
    opened = ranged(url, header, start, None, read_limit=65536)
    report(f"bytes={start}- (read 65536 then close)", opened, reference=closed)


def cmd_openended(args):
    url, header = webdav_target()
    total = file_size(url, header)
    check_open_ended("WebDAV (alist)", url, header, total, args.probe_bytes)

    token, user_id = emby_session()
    item, source, stream = emby_stream_url(token, user_id)
    print(f"\nEmby item {item['Id']} {item.get('Name')!r} container {source.get('Container')} "
          f"size {source.get('Size')}")
    emby_total = file_size(stream, "")
    check_open_ended("Emby direct play", stream, "", emby_total, args.probe_bytes)


class RangeLoggingProxy(http.server.BaseHTTPRequestHandler):
    """Forwards to one fixed upstream URL, recording Range and connection use.

    The client's own path is ignored, so the same proxy fronts a WebDAV URL whose
    credentials belong in a header and an Emby URL whose token belongs in the
    query string, and ffprobe never sees either.
    """

    protocol_version = "HTTP/1.1"
    upstream = None
    auth = None
    log = None
    lock = threading.Lock()
    connections = [0]

    def setup(self):
        super().setup()
        with self.lock:
            self.connections[0] += 1
            self.connection_index = self.connections[0]

    def log_message(self, *args):
        pass

    def do_GET(self):
        want = self.headers.get("Range")
        host, port, path = self.upstream
        upstream = http.client.HTTPConnection(host, port, timeout=300)
        headers = {"Authorization": self.auth} if self.auth else {}
        if want:
            headers["Range"] = want
        started = time.time()
        upstream.request("GET", path, headers=headers)
        response = upstream.getresponse()
        entry = {
            "conn": self.connection_index,
            "range": want,
            "status": response.status,
            "content_range": response.getheader("Content-Range"),
            "content_length": response.getheader("Content-Length"),
            "t": round(started - self.log["t0"], 3),
            "served": 0,
            "elapsed": 0.0,
        }
        with self.lock:
            self.log["requests"].append(entry)
        self.send_response(response.status)
        for name in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag"):
            value = response.getheader(name)
            if value:
                self.send_header(name, value)
        self.end_headers()
        moved = 0
        try:
            while True:
                block = response.read(65536)
                if not block:
                    break
                self.wfile.write(block)
                moved += len(block)
        except (BrokenPipeError, ConnectionResetError):
            entry["client_aborted"] = True
        entry["served"] = moved
        entry["elapsed"] = round(time.time() - started, 3)
        upstream.close()

    def do_HEAD(self):
        self.do_GET()


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def start_proxy(url, header):
    parsed = urllib.parse.urlsplit(url)
    path = parsed.path + ("?" + parsed.query if parsed.query else "")
    log = {"t0": time.time(), "requests": []}
    RangeLoggingProxy.upstream = (parsed.hostname, parsed.port or 80, path)
    RangeLoggingProxy.auth = header
    RangeLoggingProxy.log = log
    RangeLoggingProxy.connections = [0]
    server = ThreadedServer(("127.0.0.1", 0), RangeLoggingProxy)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, server.server_address[1], log


def report_requests(log):
    print(f"\nproxy saw {len(log['requests'])} requests over {RangeLoggingProxy.connections[0]} connections")
    served = 0
    for entry in log["requests"]:
        served += entry["served"]
        print(f"  t={entry['t']:>7.3f}s conn#{entry['conn']:<3} {str(entry['range']):<32} "
              f"-> {entry['status']} served {entry['served']:>10} B in {entry['elapsed']:>6.2f}s"
              f"{'  (client aborted)' if entry.get('client_aborted') else ''}")
    print(f"  total served: {served} B ({served/2**20:.2f} MiB)")


def cmd_run(args):
    if args.emby:
        token, user_id = emby_session()
        _, _, url = emby_stream_url(token, user_id)
        header = None
    else:
        url, header = webdav_target()
    command = args.command[1:] if args.command and args.command[0] == "--" else args.command
    if not command:
        sys.exit("give a command after --")
    server, port, log = start_proxy(url, header)
    environment = dict(os.environ, PROBE_URL=f"http://127.0.0.1:{port}/probe.bin")
    print(f"PROBE_URL=http://127.0.0.1:{port}/probe.bin -> {'Emby' if args.emby else 'WebDAV'}\n")
    started = time.time()
    finished = subprocess.run(command, env=environment)
    server.shutdown()
    print(f"\nexit {finished.returncode}, wall {time.time()-started:.2f}s")
    report_requests(log)


def cmd_ffprobe(args):
    url, header = webdav_target()
    server, port, log = start_proxy(url, header)

    command = ["ffprobe", "-v", "debug", "-hide_banner"]
    if args.end_offset:
        target = file_size(url, header)
        command += ["-end_offset", str(target)]
    command += list(args.extra or [])
    command += ["-show_entries", "format=format_name,duration,size:stream=index,codec_type,codec_name,channels,width,height",
                "-of", "json", "-i", f"http://127.0.0.1:{port}/probe.mp4"]

    print("command:", " ".join(command), "\n")
    started = time.time()
    finished = subprocess.run(command, capture_output=True, text=True)
    wall = time.time() - started
    server.shutdown()

    stderr = finished.stderr
    for line in stderr.splitlines():
        if re.search(r"(avformat_find_stream_info|Probe buffer size limit|probesize|analyzeduration|"
                     r"Statistics|moov atom|stream \d+, timescale|All info found|"
                     r"decoding for stream|Before avio|After avio)", line):
            print("  ffprobe |", line.strip())

    print("\nstream table:")
    try:
        print(json.dumps(json.loads(finished.stdout), indent=2, ensure_ascii=False))
    except Exception:
        print(finished.stdout[:4000] or "(no json)")

    print(f"\nwall clock {wall:.2f} s, exit {finished.returncode}")
    report_requests(log)

    stderr_path = "/tmp/ffprobe_debug.txt"
    with open(stderr_path, "w") as handle:
        handle.write(stderr)
    print(f"  full ffprobe stderr: {stderr_path}")


def cmd_playbackinfo(args):
    token, user_id = emby_session()
    result, _ = emby_request(f"/Users/{user_id}/Items", token=token, query={
        "Recursive": "true", "IncludeItemTypes": "Movie,Episode,Video",
        "SearchTerm": args.name, "Fields": "MediaSources,Path", "Limit": "5",
    })
    items = result.get("Items") or []
    if not items:
        sys.exit(f"Emby returned no item matching {args.name!r}")
    for item in items:
        sources = item.get("MediaSources") or []
        streams = sources[0].get("MediaStreams") if sources else None
        print(f"item {item['Id']} {item.get('Name')!r} path {item.get('Path')!r} "
              f"runtime {item.get('RunTimeTicks')} streams {len(streams) if streams is not None else 'n/a'}")
    item = items[0]
    for attempt in range(args.repeat):
        payload, elapsed = emby_request(f"/Items/{item['Id']}/PlaybackInfo", token=token, method="POST", body={
            "UserId": user_id, "EnableDirectPlay": True, "EnableDirectStream": True,
            "EnableTranscoding": False, "IsPlayback": True,
        })
        sources = payload.get("MediaSources") or []
        stream_count = len(sources[0].get("MediaStreams") or []) if sources else 0
        runtime = sources[0].get("RunTimeTicks") if sources else None
        print(f"  PlaybackInfo #{attempt+1}: {elapsed:.3f} s, {stream_count} media streams, "
              f"RunTimeTicks {runtime}, Size {sources[0].get('Size') if sources else None}")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("boxes").set_defaults(run=cmd_boxes)

    throughput = sub.add_parser("throughput")
    throughput.add_argument("--window", type=int, default=32 * 2**20)
    throughput.add_argument("--chunk", type=int, default=256 * 1024)
    throughput.add_argument("--chunks", type=int, default=40)
    throughput.set_defaults(run=cmd_throughput)

    openended = sub.add_parser("openended")
    openended.add_argument("--probe-bytes", type=int, default=1 << 20)
    openended.set_defaults(run=cmd_openended)

    probe = sub.add_parser("ffprobe")
    probe.add_argument("--end-offset", action="store_true")
    probe.add_argument("--extra", nargs="*")
    probe.set_defaults(run=cmd_ffprobe)

    runner = sub.add_parser("run", help="run a command with PROBE_URL pointed at the logging proxy")
    runner.add_argument("--emby", action="store_true")
    runner.add_argument("command", nargs=argparse.REMAINDER)
    runner.set_defaults(run=cmd_run)

    info = sub.add_parser("playbackinfo")
    info.add_argument("--name", default=EMBY_ITEM_NAME)
    info.add_argument("--repeat", type=int, default=2)
    info.set_defaults(run=cmd_playbackinfo)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
