#!/usr/bin/env python3
"""Relay the Sunshine port family over a second loopback base with injectable faults.

Moonlight derives every stream port from one host base address, so a client aimed at
``127.0.0.1:<listen-base>`` reaches Sunshine through this process instead of touching it
directly. A control file decides what the network does on the way through: clean
forwarding, probabilistic loss and delay, a blackhole, or a forced disconnect. Nothing
here needs root: the proxy owns its own base and never binds Sunshine's ports.

Port family relative to base ``B``::

    TCP B-5   HTTPS control      TCP B    HTTP nvhttp       TCP B+21  RTSP setup
    UDP B+9   video              UDP B+10 control           UDP B+11  audio

Faults apply per datagram and per direction, so ``udp_delay_ms`` adds twice of itself to
a round trip. Reordering swaps the scheduled delivery of two queued datagrams and
therefore needs ``udp_delay_ms`` above zero to be observable.

The GameStream client reads the media ports out of the RTSP SETUP responses, so on the
RTSP channel (base+21) the upstream-to-client direction has every ``server_port=<n>``
and ``server_port=<n>-<m>`` shifted by ``listen_base - upstream_base``. Responses are
handled whole-line, and an occurrence whose digits would change width is forwarded
untouched and logged instead. A zero offset disables the rewriting completely.

Sunshine advertises ``rtspenc://`` for clients that hold a session key; that stream is
framed binary, so the line-oriented port rewrite would hold it forever. It is relayed
untouched, and the client derives its remote ports from the address family instead.

Control file schema (missing file means ``{"mode": "pass"}``)::

    {"mode": "pass"}
    {"mode": "degrade", "udp_drop": 0.2, "udp_delay_ms": 80, "udp_reorder": 0.1,
     "tcp_delay_ms": 0}
    {"mode": "blackhole", "udp": true, "tcp": true, "disconnect": false}
    {"mode": "disconnect"}
"""

import argparse
import heapq
import json
import os
import random
import select
import shutil
import signal
import socket
import sys
import tempfile
import threading
import time

TCP_OFFSETS = (-5, 0, 21)
UDP_OFFSETS = (9, 10, 11)
RTSP_OFFSET = 21
LOOPBACK = "127.0.0.1"

DEFAULT_LISTEN_BASE = 57989
DEFAULT_UPSTREAM_BASE = 47989

CONTROL_POLL_SECONDS = 0.2
COUNTER_INTERVAL_SECONDS = 5.0
SELECT_IDLE_SECONDS = 0.2
TCP_ACCEPT_TIMEOUT_SECONDS = 0.2
TCP_PUMP_POLL_SECONDS = 0.05
TCP_CONNECT_TIMEOUT_SECONDS = 5.0
DATAGRAM_LIMIT = 65535
PREVIEW_BYTES = 32
SERVER_PORT_MARKER = b"server_port="
RTSP_BUFFER_LIMIT_BYTES = 1 << 20
PORT_MIN = 1
PORT_MAX = 65535


class Control:
    """Validated fault-injection state read from the control file."""

    __slots__ = (
        "mode",
        "udp_drop",
        "udp_delay_ms",
        "udp_reorder",
        "tcp_delay_ms",
        "blackhole_udp",
        "blackhole_tcp",
        "disconnect_tcp",
    )

    def __init__(
        self,
        mode="pass",
        udp_drop=0.0,
        udp_delay_ms=0.0,
        udp_reorder=0.0,
        tcp_delay_ms=0.0,
        blackhole_udp=False,
        blackhole_tcp=False,
        disconnect_tcp=False,
    ):
        self.mode = mode
        self.udp_drop = udp_drop
        self.udp_delay_ms = udp_delay_ms
        self.udp_reorder = udp_reorder
        self.tcp_delay_ms = tcp_delay_ms
        self.blackhole_udp = blackhole_udp
        self.blackhole_tcp = blackhole_tcp
        self.disconnect_tcp = disconnect_tcp

    def signature(self):
        return (
            self.mode,
            self.udp_drop,
            self.udp_delay_ms,
            self.udp_reorder,
            self.tcp_delay_ms,
            self.blackhole_udp,
            self.blackhole_tcp,
            self.disconnect_tcp,
        )

    def as_dict(self):
        return {
            "mode": self.mode,
            "udp_drop": self.udp_drop,
            "udp_delay_ms": self.udp_delay_ms,
            "udp_reorder": self.udp_reorder,
            "tcp_delay_ms": self.tcp_delay_ms,
            "blackhole_udp": self.blackhole_udp,
            "blackhole_tcp": self.blackhole_tcp,
            "disconnect_tcp": self.disconnect_tcp,
        }


def _fraction(doc, key):
    value = float(doc.get(key, 0.0))
    return min(max(value, 0.0), 1.0)


def _milliseconds(doc, key):
    return max(float(doc.get(key, 0.0)), 0.0)


def parse_control(doc):
    if not isinstance(doc, dict):
        raise ValueError("control document is not a JSON object")
    mode = doc.get("mode", "pass")
    if mode == "pass":
        return Control()
    if mode == "degrade":
        return Control(
            "degrade",
            udp_drop=_fraction(doc, "udp_drop"),
            udp_delay_ms=_milliseconds(doc, "udp_delay_ms"),
            udp_reorder=_fraction(doc, "udp_reorder"),
            tcp_delay_ms=_milliseconds(doc, "tcp_delay_ms"),
        )
    if mode == "blackhole":
        return Control(
            "blackhole",
            blackhole_udp=bool(doc.get("udp", True)),
            blackhole_tcp=bool(doc.get("tcp", True)),
            disconnect_tcp=bool(doc.get("disconnect", False)),
        )
    if mode == "disconnect":
        return Control("disconnect", blackhole_udp=True, blackhole_tcp=True, disconnect_tcp=True)
    raise ValueError(f"unknown mode {mode!r}")


def rtsp_rewrite_active(channel_offset, delta):
    return channel_offset == RTSP_OFFSET and delta != 0


def rewrite_server_ports(segment, offset):
    """Shift every server_port number in one complete line by ``offset``.

    Returns ``(bytes, rewrites, skips)`` where rewrites and skips hold
    ``(source_text, target_text)`` and ``(source_text, reason)`` pairs. An
    occurrence is left alone when the shift would change its digit count or
    push it out of the port range.
    """
    if offset == 0:
        return bytes(segment), [], []
    out = bytearray()
    rewrites = []
    skips = []
    cursor = 0
    length = len(segment)
    while True:
        found = segment.find(SERVER_PORT_MARKER, cursor)
        if found < 0:
            out.extend(segment[cursor:])
            break
        value_start = found + len(SERVER_PORT_MARKER)
        spans = []
        scan = value_start
        while scan < length and 48 <= segment[scan] <= 57:
            scan += 1
        if scan == value_start:
            out.extend(segment[cursor:value_start])
            cursor = value_start
            continue
        spans.append((value_start, scan))
        if scan < length and segment[scan] == 45:
            second = scan + 1
            while second < length and 48 <= segment[second] <= 57:
                second += 1
            if second > scan + 1:
                spans.append((scan + 1, second))
                scan = second
        source_text = segment[value_start:scan].decode("ascii", "replace")
        shifted = []
        reason = None
        for start, stop in spans:
            digits = segment[start:stop]
            value = int(digits) + offset
            if len(str(abs(value))) != len(digits):
                reason = "width"
                break
            if not PORT_MIN <= value <= PORT_MAX:
                reason = "range"
                break
            shifted.append(str(value))
        replacement = "-".join(shifted).encode("ascii")
        if reason is None and len(replacement) != scan - value_start:
            reason = "width"
        if reason is None:
            out.extend(segment[cursor:value_start])
            out.extend(replacement)
            rewrites.append((source_text, replacement.decode("ascii")))
        else:
            out.extend(segment[cursor:scan])
            skips.append((source_text, reason))
        cursor = scan
    return bytes(out), rewrites, skips


class TcpConnection:
    """One accepted client socket paired with its upstream socket."""

    def __init__(self, conn_id, offset, listen_base, upstream_port, peer, client, upstream):
        self.id = conn_id
        self.offset = offset
        self.listen_port = listen_base + offset
        self.upstream_port = upstream_port
        self.peer = peer
        self.client = client
        self.upstream = upstream
        self._lock = threading.Lock()
        self.closed = False
        self.reason = None
        self.bytes_to_upstream = 0
        self.bytes_to_client = 0
        self.delayed_chunks = 0
        self.delay_ms_total = 0.0
        self.rtsp_buffer = bytearray()
        self.rtsp_plaintext = None
        self.logged_rewrites = set()
        self.logged_skips = set()

    def add_bytes(self, direction, count):
        with self._lock:
            if direction == "client_to_upstream":
                self.bytes_to_upstream += count
            else:
                self.bytes_to_client += count

    def add_delay(self, milliseconds):
        with self._lock:
            self.delayed_chunks += 1
            self.delay_ms_total += milliseconds

    def close(self, reason=None):
        with self._lock:
            if reason and not self.reason:
                self.reason = reason
            if self.closed:
                return
            self.closed = True
        for sock in (self.client, self.upstream):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass


class UdpPort:
    """One relayed UDP port plus its upstream-facing socket and delay queue."""

    def __init__(self, proxy, offset, listen_sock, upstream_sock):
        self.proxy = proxy
        self.offset = offset
        self.listen_port = proxy.listen_base + offset
        self.upstream_port = proxy.upstream_base + offset
        self.listen_sock = listen_sock
        self.upstream_sock = upstream_sock
        self.client_addr = None
        self.pending = []
        self.last_entry = None
        self.next_seq = 0
        self.logged_first_to_upstream = False
        self.logged_first_to_client = False
        self.logged_send_error = False
        self.counters = {
            "client_datagrams": 0,
            "client_bytes": 0,
            "to_upstream_datagrams": 0,
            "to_upstream_bytes": 0,
            "upstream_datagrams": 0,
            "upstream_bytes": 0,
            "to_client_datagrams": 0,
            "to_client_bytes": 0,
            "dropped_random": 0,
            "dropped_blackhole": 0,
            "dropped_no_client": 0,
            "delayed": 0,
            "reordered": 0,
            "delivered": 0,
            "pending_dropped": 0,
            "pending_flushed": 0,
            "send_errors": 0,
        }

    def snapshot(self):
        data = dict(self.counters)
        data["pending"] = len(self.pending)
        data["client_addr"] = f"{self.client_addr[0]}:{self.client_addr[1]}" if self.client_addr else None
        return data


def build_listener(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LOOPBACK, port))
    sock.listen(16)
    sock.settimeout(TCP_ACCEPT_TIMEOUT_SECONDS)
    return sock


def build_udp_socket(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LOOPBACK, port))
    sock.setblocking(False)
    return sock


class Proxy:
    def __init__(
        self,
        listen_base,
        upstream_host,
        upstream_base,
        control_path,
        log_path,
        control_poll=CONTROL_POLL_SECONDS,
        duration_seconds=None,
    ):
        self.listen_base = listen_base
        self.upstream_host = upstream_host
        self.upstream_base = upstream_base
        self.offset_delta = listen_base - upstream_base
        self.control_path = control_path
        self.log_path = log_path
        self.control_poll = control_poll
        self.duration_seconds = duration_seconds

        self._lock = threading.Lock()
        self._control = Control()
        self._control_serial = 0
        self._pending_action = None
        self._control_error = None
        self._stop = threading.Event()
        self._stop_reason = "signal"
        self._stopping = False
        self._log_lock = threading.RLock()
        self._log_file = None

        self._listeners = {}
        self._udp_ports = {}
        self._connections = {}
        self._tcp_totals = {
            "connections": 0,
            "bytes_client_to_upstream": 0,
            "bytes_upstream_to_client": 0,
            "delayed_chunks": 0,
            "delay_ms_total": 0.0,
        }
        self._next_conn_id = 0
        self._threads = []
        self._wake_read, self._wake_write = socket.socketpair()
        self._wake_read.setblocking(False)
        self._wake_write.setblocking(False)
        self._wake_token = object()
        self._last_counters = 0.0
        self._random = random.Random()

    def log(self, event, **fields):
        record = {"ts": round(time.time(), 3), "event": event}
        record.update(fields)
        line = json.dumps(record, ensure_ascii=False)
        with self._log_lock:
            if self._log_file is not None:
                self._log_file.write(line + "\n")
                self._log_file.flush()

    def _note_control_error(self, message):
        if self._control_error == message:
            return
        self._control_error = message
        self.log("control_error", error=message, control=self.control_path)

    def control(self):
        with self._lock:
            return self._control

    def control_serial(self):
        with self._lock:
            return self._control_serial

    def _read_control_file(self):
        try:
            with open(self.control_path, "r", encoding="utf-8") as handle:
                return json.load(handle)
        except FileNotFoundError:
            return {"mode": "pass"}

    def _control_loop(self):
        while not self._stop.is_set():
            error = None
            control = None
            try:
                control = parse_control(self._read_control_file())
            except (OSError, ValueError, TypeError) as exc:
                error = f"{type(exc).__name__}: {exc}"
            if error is not None:
                self._note_control_error(error)
            else:
                self._control_error = None
                changed = False
                previous = None
                with self._lock:
                    if control.signature() != self._control.signature():
                        previous = self._control
                        self._control = control
                        self._control_serial += 1
                        self._pending_action = "drop" if control.blackhole_udp else "flush"
                        changed = True
                if changed:
                    self.log(
                        "mode",
                        previous=previous.mode,
                        mode=control.mode,
                        serial=self._control_serial,
                        control=control.as_dict(),
                    )
                    if control.mode == "degrade" and control.tcp_delay_ms > 0:
                        self.log("tcp_delay_active", delay_ms=control.tcp_delay_ms)
            self._stop.wait(self.control_poll)

    def _take_pending_action(self):
        with self._lock:
            action = self._pending_action
            self._pending_action = None
        return action

    def bind(self):
        for offset in TCP_OFFSETS:
            port = self.listen_base + offset
            self._listeners[offset] = build_listener(port)
        for offset in UDP_OFFSETS:
            port = self.listen_base + offset
            self._udp_ports[offset] = UdpPort(
                self,
                offset,
                build_udp_socket(port),
                socket.socket(socket.AF_INET, socket.SOCK_DGRAM),
            )

    def start(self):
        self._log_file = open(self.log_path, "a", encoding="utf-8", buffering=1)
        try:
            self.bind()
        except OSError as exc:
            self.log("bind_failed", error=f"{type(exc).__name__}: {exc}", base=self.listen_base)
            raise
        self._last_counters = time.monotonic()
        self.log(
            "listening",
            base=self.listen_base,
            listen_base=self.listen_base,
            upstream=f"{self.upstream_host}:{self.upstream_base}",
            control=self.control_path,
            tcp=sorted(self.listen_base + offset for offset in TCP_OFFSETS),
            udp=sorted(self.listen_base + offset for offset in UDP_OFFSETS),
        )
        for offset, listener in sorted(self._listeners.items()):
            self.log("listening", base=self.listen_base, proto="tcp", offset=offset, port=listener.getsockname()[1])
        for offset, port in sorted(self._udp_ports.items()):
            self.log("listening", base=self.listen_base, proto="udp", offset=offset, port=port.listen_sock.getsockname()[1])
        self.log("session", phase="start", base=self.listen_base)

        self._spawn(self._control_loop, "control")
        self._spawn(self._udp_loop, "udp")
        for offset, listener in sorted(self._listeners.items()):
            self._spawn(self._tcp_accept_loop, "tcp-accept", offset, listener)
        if self.duration_seconds:
            self._spawn(self._duration_loop, "duration")

    def _spawn(self, target, name, *args):
        thread = threading.Thread(target=target, args=args, name=f"moonlight-proxy-{name}", daemon=True)
        thread.start()
        self._threads.append(thread)
        return thread

    def run(self):
        for signum in (signal.SIGTERM, signal.SIGINT):
            signal.signal(signum, self._handle_signal)
        self.start()
        self._stop.wait()
        self.shutdown(self._stop_reason)
        return 0

    def _duration_loop(self):
        self.log("duration", seconds=self.duration_seconds)
        if self._stop.wait(self.duration_seconds):
            return
        self.log("duration_elapsed", seconds=self.duration_seconds)
        self._stop_reason = "duration"
        self._stop.set()
        self._wake()

    def _handle_signal(self, signum, _frame):
        self._stop_reason = "signal"
        self.log("signal", signal=signal.Signals(signum).name)
        self._stop.set()
        self._wake()

    def _wake(self):
        try:
            self._wake_write.send(b"\x00")
        except OSError:
            pass

    def shutdown(self, reason):
        if self._stopping:
            return
        self._stopping = True
        self._stop.set()
        self._wake()
        for listener in self._listeners.values():
            try:
                listener.close()
            except OSError:
                pass
        for port in self._udp_ports.values():
            try:
                port.listen_sock.close()
            except OSError:
                pass
            try:
                port.upstream_sock.close()
            except OSError:
                pass
        for thread in self._threads:
            thread.join(timeout=1.0)
        with self._lock:
            connections = list(self._connections.values())
        for connection in connections:
            connection.close("shutdown")
        self.log("session", phase="stop", base=self.listen_base, reason=reason)
        self.log("shutdown", reason=reason, tcp_counters=self._tcp_counters(), udp_counters=self._udp_counters())
        with self._log_lock:
            if self._log_file is not None:
                self._log_file.flush()
                self._log_file.close()
                self._log_file = None
        try:
            self._wake_read.close()
            self._wake_write.close()
        except OSError:
            pass

    def _tcp_counters(self):
        with self._lock:
            return dict(self._tcp_totals)

    def _udp_counters(self):
        return {str(port.listen_port): port.snapshot() for port in sorted(self._udp_ports.values(), key=lambda p: p.offset)}

    def _tcp_accept_loop(self, offset, listener):
        while not self._stop.is_set():
            try:
                client, peer = listener.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            with self._lock:
                conn_id = self._next_conn_id
                self._next_conn_id += 1
            self._spawn(self._tcp_session, f"tcp-{offset}-{conn_id}", conn_id, offset, client, peer)

    def _tcp_session(self, conn_id, offset, client, peer):
        upstream_port = self.upstream_base + offset
        listen_port = self.listen_base + offset
        control = self.control()
        if control.disconnect_tcp:
            self.log("tcp_refused", id=conn_id, port=listen_port, offset=offset, peer=f"{peer[0]}:{peer[1]}", reason="disconnect")
            client.close()
            return
        started = time.monotonic()
        try:
            upstream = socket.create_connection((self.upstream_host, upstream_port), timeout=TCP_CONNECT_TIMEOUT_SECONDS)
        except OSError as exc:
            self.log(
                "tcp_connect_failed",
                id=conn_id,
                port=listen_port,
                offset=offset,
                peer=f"{peer[0]}:{peer[1]}",
                upstream=f"{self.upstream_host}:{upstream_port}",
                error=f"{type(exc).__name__}: {exc}",
            )
            client.close()
            return
        upstream.settimeout(None)
        connection = TcpConnection(conn_id, offset, self.listen_base, upstream_port, peer, client, upstream)
        with self._lock:
            self._connections[conn_id] = connection
        self.log(
            "tcp_connect",
            id=conn_id,
            port=listen_port,
            offset=offset,
            peer=f"{peer[0]}:{peer[1]}",
            upstream=f"{self.upstream_host}:{upstream_port}",
        )
        pumps = [
            self._spawn(self._tcp_pump, f"tcp-{conn_id}-up", connection, connection.client, connection.upstream, "client_to_upstream"),
            self._spawn(self._tcp_pump, f"tcp-{conn_id}-down", connection, connection.upstream, connection.client, "upstream_to_client"),
        ]
        while not self._stop.is_set() and any(pump.is_alive() for pump in pumps):
            for pump in pumps:
                pump.join(timeout=TCP_PUMP_POLL_SECONDS * 4)
        if rtsp_rewrite_active(offset, self.offset_delta) and connection.rtsp_plaintext is not False:
            self._flush_rtsp_tail(connection)
        connection.close()
        with self._lock:
            self._connections.pop(conn_id, None)
            self._tcp_totals["connections"] += 1
            self._tcp_totals["bytes_client_to_upstream"] += connection.bytes_to_upstream
            self._tcp_totals["bytes_upstream_to_client"] += connection.bytes_to_client
            self._tcp_totals["delayed_chunks"] += connection.delayed_chunks
            self._tcp_totals["delay_ms_total"] += connection.delay_ms_total
        self.log(
            "tcp_close",
            id=conn_id,
            port=listen_port,
            offset=offset,
            reason=connection.reason or "eof",
            seconds=round(time.monotonic() - started, 3),
            bytes_client_to_upstream=connection.bytes_to_upstream,
            bytes_upstream_to_client=connection.bytes_to_client,
            delayed_chunks=connection.delayed_chunks,
            delay_ms_total=round(connection.delay_ms_total, 1),
        )

    def _tcp_pump(self, connection, src, dst, direction):
        rewrite = direction == "upstream_to_client" and rtsp_rewrite_active(connection.offset, self.offset_delta)
        while not self._stop.is_set():
            control = self.control()
            if control.disconnect_tcp or connection.closed:
                connection.reason = connection.reason or "disconnect"
                return
            if control.blackhole_tcp:
                time.sleep(TCP_PUMP_POLL_SECONDS)
                continue
            try:
                readable, _, _ = select.select([src], [], [], TCP_PUMP_POLL_SECONDS)
            except (OSError, ValueError):
                connection.reason = connection.reason or "socket_error"
                return
            if not readable:
                continue
            try:
                data = src.recv(65536)
            except OSError:
                connection.reason = connection.reason or "socket_error"
                try:
                    dst.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                return
            if not data:
                connection.reason = connection.reason or "eof"
                try:
                    dst.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                return
            if direction == "client_to_upstream" and connection.rtsp_plaintext is None:
                connection.rtsp_plaintext = data[:8].startswith(b"OPTIONS ") or data[:4] == b"RTSP"
                if not connection.rtsp_plaintext:
                    self.log(
                        "rtsp_opaque",
                        id=connection.id,
                        port=connection.listen_port,
                        offset=connection.offset,
                    )
            if rewrite and connection.rtsp_plaintext is not False:
                data = self._rewrite_rtsp_chunk(connection, data)
                if not data:
                    continue
            if control.tcp_delay_ms > 0:
                time.sleep(control.tcp_delay_ms / 1000.0)
                connection.add_delay(control.tcp_delay_ms)
            try:
                dst.sendall(data)
            except OSError:
                connection.reason = connection.reason or "socket_error"
                return
            connection.add_bytes(direction, len(data))

    def _rewrite_rtsp_chunk(self, connection, data):
        buffer = connection.rtsp_buffer
        buffer.extend(data)
        boundary = buffer.rfind(b"\n")
        if boundary < 0:
            if len(buffer) < RTSP_BUFFER_LIMIT_BYTES:
                return b""
            segment = bytes(buffer)
            buffer.clear()
        else:
            segment = bytes(buffer[: boundary + 1])
            del buffer[: boundary + 1]
        return self._rewrite_rtsp_segment(connection, segment)

    def _rewrite_rtsp_segment(self, connection, segment):
        rewritten, rewrites, skips = rewrite_server_ports(segment, self.offset_delta)
        for source, target in rewrites:
            key = (source, target)
            if key in connection.logged_rewrites:
                continue
            connection.logged_rewrites.add(key)
            self.log(
                "rtsp_rewrite",
                **{"id": connection.id, "port": connection.listen_port, "offset": self.offset_delta, "from": source, "to": target},
            )
        for source, reason in skips:
            key = (source, reason)
            if key in connection.logged_skips:
                continue
            connection.logged_skips.add(key)
            self.log(
                "rtsp_rewrite_skipped",
                **{"id": connection.id, "port": connection.listen_port, "offset": self.offset_delta, "from": source, "reason": reason},
            )
        return rewritten

    def _flush_rtsp_tail(self, connection):
        tail = bytes(connection.rtsp_buffer)
        connection.rtsp_buffer.clear()
        if not tail:
            return
        try:
            connection.client.sendall(tail)
        except OSError:
            pass

    def _udp_loop(self):
        sources = {}
        for port in self._udp_ports.values():
            sources[port.listen_sock] = (port, True)
            sources[port.upstream_sock] = (port, False)
        sources[self._wake_read] = (self._wake_token, None)
        while not self._stop.is_set():
            action = self._take_pending_action()
            if action == "drop":
                self._drop_pending()
            elif action == "flush":
                self._flush_pending()
            try:
                ready, _, _ = select.select(list(sources), [], [], self._udp_timeout())
            except (OSError, ValueError):
                continue
            for sock in ready:
                port, to_upstream = sources[sock]
                if port is self._wake_token:
                    try:
                        self._wake_read.recv(64)
                    except OSError:
                        pass
                    continue
                if to_upstream:
                    self._recv_from_client(port)
                else:
                    self._recv_from_upstream(port)
            self._drain_pending()
            self._log_counters()

    def _udp_timeout(self):
        timeout = SELECT_IDLE_SECONDS
        now = time.monotonic()
        for port in self._udp_ports.values():
            if port.pending:
                timeout = min(timeout, max(0.0, port.pending[0][0] - now))
        return timeout

    def _recv_from_client(self, port):
        try:
            data, addr = port.listen_sock.recvfrom(DATAGRAM_LIMIT)
        except OSError:
            return
        port.client_addr = addr
        port.counters["client_datagrams"] += 1
        port.counters["client_bytes"] += len(data)
        if not port.logged_first_to_upstream:
            port.logged_first_to_upstream = True
            self.log(
                "udp_first_datagram",
                port=port.listen_port,
                offset=port.offset,
                direction="client_to_upstream",
                client=f"{addr[0]}:{addr[1]}",
                upstream=f"{self.upstream_host}:{port.upstream_port}",
                bytes=len(data),
                preview=data[:PREVIEW_BYTES].hex(),
            )
        self._relay(port, data, True)

    def _recv_from_upstream(self, port):
        try:
            data, addr = port.upstream_sock.recvfrom(DATAGRAM_LIMIT)
        except OSError:
            return
        port.counters["upstream_datagrams"] += 1
        port.counters["upstream_bytes"] += len(data)
        if port.client_addr is None:
            port.counters["dropped_no_client"] += 1
            return
        if not port.logged_first_to_client:
            port.logged_first_to_client = True
            self.log(
                "udp_first_reply",
                port=port.listen_port,
                offset=port.offset,
                direction="upstream_to_client",
                source=f"{addr[0]}:{addr[1]}",
                client=f"{port.client_addr[0]}:{port.client_addr[1]}",
                bytes=len(data),
                preview=data[:PREVIEW_BYTES].hex(),
            )
        self._relay(port, data, False)

    def _relay(self, port, data, to_upstream):
        control = self.control()
        if control.blackhole_udp:
            port.counters["dropped_blackhole"] += 1
            return
        if control.mode == "degrade":
            if control.udp_drop > 0 and self._random.random() < control.udp_drop:
                port.counters["dropped_random"] += 1
                return
            if control.udp_delay_ms > 0:
                self._schedule(port, data, to_upstream, control.udp_delay_ms)
                return
        self._send(port, data, to_upstream)

    def _schedule(self, port, data, to_upstream, delay_ms):
        due = time.monotonic() + delay_ms / 1000.0
        entry = [due, port.next_seq, data, to_upstream]
        port.next_seq += 1
        control = self.control()
        if port.pending and control.udp_reorder > 0 and self._random.random() < control.udp_reorder:
            if port.last_entry is not None and any(item is port.last_entry for item in port.pending):
                port.last_entry[0], entry[0] = entry[0], port.last_entry[0]
                heapq.heapify(port.pending)
                port.counters["reordered"] += 1
        heapq.heappush(port.pending, entry)
        port.last_entry = entry
        port.counters["delayed"] += 1

    def _drain_pending(self):
        now = time.monotonic()
        for port in self._udp_ports.values():
            while port.pending and port.pending[0][0] <= now:
                entry = heapq.heappop(port.pending)
                port.counters["delivered"] += 1
                self._send(port, entry[2], entry[3])
            if port.last_entry is not None and not port.pending:
                port.last_entry = None

    def _drop_pending(self):
        dropped = 0
        for port in self._udp_ports.values():
            dropped += len(port.pending)
            port.counters["pending_dropped"] += len(port.pending)
            port.pending.clear()
            port.last_entry = None
        if dropped:
            self.log("udp_pending_dropped", count=dropped)

    def _flush_pending(self):
        flushed = 0
        for port in self._udp_ports.values():
            while port.pending:
                entry = heapq.heappop(port.pending)
                port.counters["pending_flushed"] += 1
                port.counters["delivered"] += 1
                self._send(port, entry[2], entry[3])
                flushed += 1
            port.last_entry = None
        if flushed:
            self.log("udp_pending_flushed", count=flushed)

    def _send(self, port, data, to_upstream):
        if to_upstream:
            try:
                port.upstream_sock.sendto(data, (self.upstream_host, port.upstream_port))
            except OSError as exc:
                port.counters["send_errors"] += 1
                if not port.logged_send_error:
                    port.logged_send_error = True
                    self.log("udp_send_error", port=port.listen_port, direction="client_to_upstream", error=f"{type(exc).__name__}: {exc}")
                return
            port.counters["to_upstream_datagrams"] += 1
            port.counters["to_upstream_bytes"] += len(data)
            return
        if port.client_addr is None:
            port.counters["dropped_no_client"] += 1
            return
        try:
            port.listen_sock.sendto(data, port.client_addr)
        except OSError as exc:
            port.counters["send_errors"] += 1
            if not port.logged_send_error:
                port.logged_send_error = True
                self.log("udp_send_error", port=port.listen_port, direction="upstream_to_client", error=f"{type(exc).__name__}: {exc}")
            return
        port.counters["to_client_datagrams"] += 1
        port.counters["to_client_bytes"] += len(data)

    def _log_counters(self):
        now = time.monotonic()
        if now - self._last_counters < COUNTER_INTERVAL_SECONDS:
            return
        window = round(now - self._last_counters, 3)
        self._last_counters = now
        self.log("udp_counters", window_seconds=window, ports=self._udp_counters())


def receive_exactly(sock, count, timeout):
    sock.settimeout(timeout)
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            break
        data += chunk
    return data


def tcp_echo_round_trip(port, payload, timeout):
    with socket.create_connection((LOOPBACK, port), timeout=timeout) as sock:
        sock.sendall(payload)
        return receive_exactly(sock, len(payload), timeout)


def udp_client(timeout):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LOOPBACK, 0))
    sock.settimeout(timeout)
    return sock


def udp_echo_round_trip(port, payload, timeout):
    with udp_client(timeout) as sock:
        sock.sendto(payload, (LOOPBACK, port))
        data, _ = sock.recvfrom(DATAGRAM_LIMIT)
        return data


def rtsp_client_exchange(port, request, timeout):
    with socket.create_connection((LOOPBACK, port), timeout=timeout) as sock:
        sock.sendall(request)
        sock.settimeout(timeout)
        data = b""
        while not data.endswith(b"\r\n\r\n"):
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
        return data


def framed_client_exchange(port, request, timeout, expected_bytes):
    with socket.create_connection((LOOPBACK, port), timeout=timeout) as sock:
        sock.sendall(request)
        return receive_exactly(sock, expected_bytes, timeout)


class TcpEchoServer:
    def __init__(self, port):
        self.listener = build_listener(port)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self.thread.start()

    def _serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.listener.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            threading.Thread(target=self._echo, args=(conn,), daemon=True).start()

    def _echo(self, conn):
        try:
            conn.settimeout(0.5)
            while not self.stop.is_set():
                try:
                    data = conn.recv(65536)
                except TimeoutError:
                    continue
                except OSError:
                    return
                if not data:
                    return
                try:
                    conn.sendall(data)
                except OSError:
                    return
        finally:
            conn.close()

    def close(self):
        self.stop.set()
        try:
            self.listener.close()
        except OSError:
            pass


class RtspFixtureServer:
    """Answers every request line with a canned RTSP SETUP style response.

    The encrypted dialect (rtspenc) is framed binary: it is answered with framed
    binary that carries the same port marker the plaintext response uses, so a
    rewrite would be visible.
    """

    def __init__(self, port, response, small_response):
        self.listener = build_listener(port)
        self.response = response
        self.small_response = small_response
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self.thread.start()

    def _serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.listener.accept()
            except TimeoutError:
                continue
            except OSError:
                return
            threading.Thread(target=self._session, args=(conn,), daemon=True).start()

    def _session(self, conn):
        try:
            conn.settimeout(0.5)
            while not self.stop.is_set():
                try:
                    request = conn.recv(4096)
                except TimeoutError:
                    continue
                except OSError:
                    return
                if not request:
                    return
                if not (request[:8].startswith(b"OPTIONS ") or request[:4] == b"RTSP"):
                    try:
                        conn.sendall(BINARY_RTSP_FIXTURE_RESPONSE)
                    except OSError:
                        return
                    continue
                payload = self.small_response if b"SMALL" in request else self.response
                try:
                    if b"SPLIT" in request:
                        marker = payload.index(SERVER_PORT_MARKER) + len(SERVER_PORT_MARKER) + 3
                        conn.sendall(payload[:marker])
                        time.sleep(0.05)
                        conn.sendall(payload[marker:])
                    else:
                        conn.sendall(payload)
                except OSError:
                    return
        finally:
            conn.close()

    def close(self):
        self.stop.set()
        try:
            self.listener.close()
        except OSError:
            pass


class UdpEchoServer:
    def __init__(self, port):
        self.sock = build_udp_socket(port)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self.thread.start()

    def _serve(self):
        while not self.stop.is_set():
            try:
                ready, _, _ = select.select([self.sock], [], [], SELECT_IDLE_SECONDS)
            except OSError:
                return
            if not ready:
                continue
            try:
                data, addr = self.sock.recvfrom(DATAGRAM_LIMIT)
                self.sock.sendto(data, addr)
            except OSError:
                return

    def close(self):
        self.stop.set()
        try:
            self.sock.close()
        except OSError:
            pass


def family_ports(base):
    return sorted({base + offset for offset in TCP_OFFSETS} | {base + offset for offset in UDP_OFFSETS})


def ports_available(tcp_ports, udp_ports):
    holders = []
    try:
        for port in tcp_ports:
            holders.append(build_listener(port))
        for port in udp_ports:
            holders.append(build_udp_socket(port))
    except OSError:
        return False
    finally:
        for sock in holders:
            try:
                sock.close()
            except OSError:
                pass
    return True


def pick_bases(rng):
    for _ in range(500):
        listen_base = rng.randrange(20000, 60000)
        upstream_base = rng.randrange(20000, 60000)
        ports = set(family_ports(listen_base)) | {upstream_base, upstream_base + 9}
        if len(ports) != len(family_ports(listen_base)) + 2:
            continue
        if not all(1024 < port < 65536 for port in ports):
            continue
        tcp_ports = sorted({listen_base + offset for offset in TCP_OFFSETS} | {upstream_base})
        udp_ports = sorted({listen_base + offset for offset in UDP_OFFSETS} | {upstream_base + 9})
        if ports_available(tcp_ports, udp_ports):
            return listen_base, upstream_base
    raise RuntimeError("no free port family found for the self test")


def pick_rtsp_base(rng, delta):
    for _ in range(500):
        upstream_base = rng.randrange(20000, 55000 - delta)
        listen_base = upstream_base + delta
        tcp_ports = {upstream_base + RTSP_OFFSET} | {listen_base + offset for offset in TCP_OFFSETS}
        udp_ports = {listen_base + offset for offset in UDP_OFFSETS}
        if len(tcp_ports) + len(udp_ports) != len(tcp_ports | udp_ports):
            continue
        if not all(1024 < port < 65536 for port in tcp_ports | udp_ports):
            continue
        if ports_available(sorted(tcp_ports), sorted(udp_ports)):
            return upstream_base
    raise RuntimeError("no free port family found for the RTSP self test")


RTSP_TEST_DELTA = 10000
RTSP_FIXTURE_RESPONSE = b"RTSP/1.0 200 OK\r\nTransport: unicast;server_port=47998-47999;client_port=12345-12346\r\n\r\n"
RTSP_FIXTURE_SMALL_RESPONSE = b"RTSP/1.0 200 OK\r\nTransport: unicast;server_port=4798-4799;client_port=12345-12346\r\n\r\n"
BINARY_RTSP_BODY = b"server_port=47998-47999;cipher"
BINARY_RTSP_FIXTURE_RESPONSE = (
    len(BINARY_RTSP_BODY).to_bytes(4, "big") + b"\x00\x00\x00\x01" + BINARY_RTSP_BODY
)


def run_self_test():
    rng = random.Random()
    listen_base, upstream_base = pick_bases(rng)
    rtsp_upstream_base = pick_rtsp_base(rng, RTSP_TEST_DELTA)
    workdir = tempfile.mkdtemp(prefix="moonlight-proxy-selftest-")
    control_path = os.path.join(workdir, "control.json")
    log_path = os.path.join(workdir, "proxy.jsonl")
    rtsp_control_path = os.path.join(workdir, "rtsp_control.json")
    rtsp_log_path = os.path.join(workdir, "rtsp_proxy.jsonl")
    with open(rtsp_control_path, "w", encoding="utf-8") as handle:
        json.dump({"mode": "pass"}, handle)
    tcp_echo = TcpEchoServer(upstream_base)
    udp_echo = UdpEchoServer(upstream_base + 9)
    rtsp_fixture = RtspFixtureServer(rtsp_upstream_base + RTSP_OFFSET, RTSP_FIXTURE_RESPONSE, RTSP_FIXTURE_SMALL_RESPONSE)
    proxy = Proxy(
        listen_base=listen_base,
        upstream_host=LOOPBACK,
        upstream_base=upstream_base,
        control_path=control_path,
        log_path=log_path,
        control_poll=0.05,
    )
    rtsp_proxy = Proxy(
        listen_base=rtsp_upstream_base + RTSP_TEST_DELTA,
        upstream_host=LOOPBACK,
        upstream_base=rtsp_upstream_base,
        control_path=rtsp_control_path,
        log_path=rtsp_log_path,
        control_poll=0.05,
    )
    failures = []
    print(f"self test bases: listen={listen_base} upstream={upstream_base} rtsp listen={rtsp_upstream_base + RTSP_TEST_DELTA} rtsp upstream={rtsp_upstream_base} workdir={workdir}")

    def check(name, function):
        try:
            detail = function()
        except Exception as exc:
            failures.append((name, f"{type(exc).__name__}: {exc}"))
            print(f"  FAIL {name}: {type(exc).__name__}: {exc}")
        else:
            suffix = f" ({detail})" if detail else ""
            print(f"  ok   {name}{suffix}")

    def set_mode(document):
        serial = proxy.control_serial()
        temporary = control_path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(document, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, control_path)
        deadline = time.monotonic() + 2.0
        while proxy.control_serial() == serial:
            if time.monotonic() > deadline:
                raise AssertionError(f"control change {document} was not applied within 2 s")
            time.sleep(0.02)

    def drain_udp(sock, seconds=0.3):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                sock.recvfrom(DATAGRAM_LIMIT)
            except TimeoutError:
                return

    tcp_echo.start()
    udp_echo.start()
    rtsp_fixture.start()
    try:
        proxy.start()
        rtsp_proxy.start()

        def test_pass():
            payload = os.urandom(64)
            if tcp_echo_round_trip(listen_base, payload, 2.0) != payload:
                raise AssertionError("TCP echo payload mismatch")
            datagram = os.urandom(48)
            if udp_echo_round_trip(listen_base + 9, datagram, 2.0) != datagram:
                raise AssertionError("UDP echo payload mismatch")
            return f"tcp={len(payload)}B udp={len(datagram)}B byte-exact"

        def test_drop():
            set_mode({"mode": "degrade", "udp_drop": 1.0, "udp_delay_ms": 0, "udp_reorder": 0, "tcp_delay_ms": 0})
            with udp_client(0.2) as sock:
                drain_udp(sock)
                for _ in range(5):
                    sock.sendto(os.urandom(32), (LOOPBACK, listen_base + 9))
                received = 0
                deadline = time.monotonic() + 1.0
                while time.monotonic() < deadline:
                    try:
                        sock.recvfrom(DATAGRAM_LIMIT)
                        received += 1
                    except TimeoutError:
                        continue
            if received:
                raise AssertionError(f"expected no UDP echo under udp_drop=1.0, got {received}")
            payload = os.urandom(32)
            if tcp_echo_round_trip(listen_base, payload, 2.0) != payload:
                raise AssertionError("TCP echo broke while only UDP was degraded")
            return "0/5 udp echoes, tcp intact"

        def test_delay():
            set_mode({"mode": "degrade", "udp_drop": 0.0, "udp_delay_ms": 200, "udp_reorder": 0.0, "tcp_delay_ms": 0})
            datagram = os.urandom(40)
            with udp_client(3.0) as sock:
                drain_udp(sock)
                started = time.monotonic()
                sock.sendto(datagram, (LOOPBACK, listen_base + 9))
                data, _ = sock.recvfrom(DATAGRAM_LIMIT)
                elapsed = time.monotonic() - started
            if data != datagram:
                raise AssertionError("delayed UDP echo payload mismatch")
            if elapsed < 0.15:
                raise AssertionError(f"echo arrived after {elapsed:.3f} s, expected at least 0.15 s")
            return f"round trip {elapsed:.3f} s"

        def test_blackhole():
            set_mode({"mode": "blackhole", "udp": False, "tcp": True})
            datagram = os.urandom(24)
            if udp_echo_round_trip(listen_base + 9, datagram, 1.5) != datagram:
                raise AssertionError("UDP echo broke while only TCP was blackholed")
            with socket.create_connection((LOOPBACK, listen_base), timeout=2.0) as sock:
                sock.settimeout(1.0)
                sock.sendall(b"blackhole-probe")
                try:
                    data = sock.recv(64)
                except TimeoutError:
                    pass
                else:
                    raise AssertionError(f"blackholed TCP returned {data!r}")
                time.sleep(2.2)
                try:
                    late = sock.recv(64)
                except TimeoutError:
                    return "tcp timed out and stayed open, udp intact"
                if late == b"":
                    raise AssertionError("blackholed TCP connection was closed, expected it to stay open")
                raise AssertionError(f"blackholed TCP returned {late!r}")

        def test_disconnect():
            set_mode({"mode": "pass"})
            payload = os.urandom(16)
            sock = socket.create_connection((LOOPBACK, listen_base), timeout=2.0)
            sock.sendall(payload)
            if receive_exactly(sock, len(payload), 2.0) != payload:
                sock.close()
                raise AssertionError("TCP echo did not work before the disconnect")
            set_mode({"mode": "disconnect"})
            started = time.monotonic()
            try:
                data = sock.recv(16)
            except (TimeoutError, ConnectionResetError) as exc:
                data = b"" if isinstance(exc, ConnectionResetError) else None
            elapsed = time.monotonic() - started
            sock.close()
            if data is None:
                raise AssertionError("connection stayed open past 2 s under disconnect mode")
            if data != b"":
                raise AssertionError(f"expected EOF, got {data!r}")
            return f"EOF after {elapsed:.3f} s"

        def test_rtsp_rewrite():
            canonical = RTSP_FIXTURE_RESPONSE
            expected = canonical.replace(b"server_port=47998-47999;", b"server_port=57998-57999;")
            if rewrite_server_ports(canonical, 0) != (canonical, [], []):
                raise AssertionError("offset 0 must leave every byte alone")
            if rtsp_rewrite_active(RTSP_OFFSET, 0) or rtsp_rewrite_active(0, RTSP_TEST_DELTA):
                raise AssertionError("rewriting must be off without an offset and off the RTSP channel")
            rewritten, rewrites, skips = rewrite_server_ports(canonical, RTSP_TEST_DELTA)
            if rewritten != expected or rewrites != [("47998-47999", "57998-57999")] or skips:
                raise AssertionError(f"unexpected rewrite {rewrites} {skips}: {rewritten!r}")
            unchanged, rewrites, skips = rewrite_server_ports(canonical, 200000)
            if unchanged != canonical or rewrites or [reason for _, reason in skips] != ["width"]:
                raise AssertionError(f"width-changing offset must skip, got {rewrites} {skips}")
            response = rtsp_client_exchange(rtsp_upstream_base + RTSP_TEST_DELTA + RTSP_OFFSET, b"OPTIONS * RTSP/1.0\r\n\r\n", 2.0)
            if response != expected:
                raise AssertionError(f"proxied SETUP response {response!r} != {expected!r}")
            events = [json.loads(line) for line in open(rtsp_log_path, encoding="utf-8")]
            if not any(
                event["event"] == "rtsp_rewrite" and event["from"] == "47998-47999" and event["to"] == "57998-57999" for event in events
            ):
                raise AssertionError("rtsp_rewrite event missing from the RTSP proxy log")
            small = rtsp_client_exchange(rtsp_upstream_base + RTSP_TEST_DELTA + RTSP_OFFSET, b"OPTIONS * RTSP/1.0 SMALL\r\n\r\n", 2.0)
            if small != RTSP_FIXTURE_SMALL_RESPONSE:
                raise AssertionError(f"width-changing line was not forwarded verbatim: {small!r}")
            split = rtsp_client_exchange(rtsp_upstream_base + RTSP_TEST_DELTA + RTSP_OFFSET, b"OPTIONS * RTSP/1.0 SPLIT\r\n\r\n", 2.0)
            if split != expected:
                raise AssertionError(f"response split across segments was not reassembled: {split!r}")
            events = [json.loads(line) for line in open(rtsp_log_path, encoding="utf-8")]
            if not any(
                event["event"] == "rtsp_rewrite_skipped" and event["reason"] == "width" and event["from"] == "4798-4799" for event in events
            ):
                raise AssertionError("rtsp_rewrite_skipped event missing from the RTSP proxy log")
            return f"server_port 47998-47999 -> 57998-57999, client_port untouched, width skip logged"

        def test_rtsp_opaque():
            request = bytes(range(120))
            response = framed_client_exchange(
                rtsp_upstream_base + RTSP_TEST_DELTA + RTSP_OFFSET,
                request,
                2.0,
                len(BINARY_RTSP_FIXTURE_RESPONSE),
            )
            if response != BINARY_RTSP_FIXTURE_RESPONSE:
                raise AssertionError(
                    "framed (rtspenc) response was altered: "
                    f"{response!r} != {BINARY_RTSP_FIXTURE_RESPONSE!r}"
                )
            events = [json.loads(line) for line in open(rtsp_log_path, encoding="utf-8")]
            if not any(event["event"] == "rtsp_opaque" for event in events):
                raise AssertionError("rtsp_opaque event missing from the RTSP proxy log")
            plaintext = rtsp_client_exchange(
                rtsp_upstream_base + RTSP_TEST_DELTA + RTSP_OFFSET, b"OPTIONS * RTSP/1.0\r\n\r\n", 2.0
            )
            expected = RTSP_FIXTURE_RESPONSE.replace(
                b"server_port=47998-47999;", b"server_port=57998-57999;"
            )
            if plaintext != expected:
                raise AssertionError(
                    f"plaintext RTSP stopped being rewritten after a framed session: {plaintext!r}"
                )
            return f"{len(request)}B frame relayed byte-exactly, plaintext rewriting still active"

        check("pass mode forwards TCP and UDP byte-exactly", test_pass)
        check("udp_drop=1.0 loses all UDP, TCP survives", test_drop)
        check("udp_delay_ms=200 delays the echo", test_delay)
        check("blackhole tcp=true, udp=false times out TCP only", test_blackhole)
        check("disconnect closes an established TCP connection", test_disconnect)
        check(f"rtsp server_port rewriting at offset +{RTSP_TEST_DELTA}", test_rtsp_rewrite)
        check("framed rtspenc traffic is relayed without rewriting", test_rtsp_opaque)
    finally:
        proxy.shutdown("self-test")
        rtsp_proxy.shutdown("self-test")
        tcp_echo.close()
        udp_echo.close()
        rtsp_fixture.close()

    if failures:
        print(f"SELFTEST FAILED ({len(failures)} of 6 checks): {failures}")
        print(f"artifacts kept in {workdir}")
        return 1
    print("SELFTEST OK")
    shutil.rmtree(workdir, ignore_errors=True)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Loopback proxy for the Moonlight/Sunshine port family with injectable network faults.")
    parser.add_argument("--listen-base", type=int, default=DEFAULT_LISTEN_BASE, help="base of the family the proxy listens on (default %(default)s)")
    parser.add_argument("--upstream-host", default=LOOPBACK, help="Sunshine host (default %(default)s)")
    parser.add_argument("--upstream-base", type=int, default=DEFAULT_UPSTREAM_BASE, help="base of the family Sunshine serves (default %(default)s)")
    parser.add_argument("--control", help="fault-injection control file, polled every 200 ms")
    parser.add_argument("--log", help="JSONL event log")
    parser.add_argument("--duration-seconds", type=float, help="exit after this many seconds instead of waiting for a signal")
    parser.add_argument("--self-test", action="store_true", help="run the embedded self test against in-process echo servers and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()
    if not args.control or not args.log:
        parser.error("--control and --log are required unless --self-test is used")
    if args.duration_seconds is not None and args.duration_seconds <= 0:
        parser.error("--duration-seconds must be positive")
    for base, label in ((args.listen_base, "--listen-base"), (args.upstream_base, "--upstream-base")):
        for port in family_ports(base):
            if not 1024 < port < 65536:
                parser.error(f"{label} basis is unusable: family port {port} is out of range")
    if args.upstream_host in ("127.0.0.1", "localhost") and set(family_ports(args.listen_base)) & set(family_ports(args.upstream_base)):
        parser.error("--listen-base and --upstream-base families overlap on the loopback host")

    proxy = Proxy(
        listen_base=args.listen_base,
        upstream_host=args.upstream_host,
        upstream_base=args.upstream_base,
        control_path=args.control,
        log_path=args.log,
        duration_seconds=args.duration_seconds,
    )
    try:
        return proxy.run()
    except OSError as exc:
        print(f"moonlight_loopback_proxy: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
