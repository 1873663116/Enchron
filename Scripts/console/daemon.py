from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from model import TIER_ORDER
import transport

CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
RUNNER_BUNDLE = "com.xiongzhipeng.EnchronAppUITests.xctrunner"
BUILD_PRODUCTS = ".scratch/build/Build/Products"
SESSION_RECORD = ".console/session.json"
RUNNER_SPEC = "InteractiveDeviceSession"
READY_TIMEOUT = 300.0
from vocab import VERBS


CHANNEL_SCRIPT = Path("Scripts/console/transport.py")
IDLE_EXIT_SECONDS = 900.0
START_DEADLINE_SECONDS = 15.0
BUILD_PRODUCTS = Path(".scratch/build/Build/Products")
RUNNER_SPEC = "InteractiveDeviceSession"
CHANNEL_ROOT = "Documents/EnchronInteractiveUI"
READY_TIMEOUT_SECONDS = 300.0


def socket_path(root: Path) -> Path:
    return root / ".console" / "daemon.sock"


def state_path(root: Path) -> Path:
    return root / ".console" / "daemon.json"


def log_path(root: Path) -> Path:
    return root / ".console" / "daemon.log"


class Channel:
    def __init__(self, root: Path, target: str) -> None:
        self.root = root
        self.target = target
        self.session_ready = False
        self.ready: dict[str, Any] | None = None
        self.runner: subprocess.Popen | None = None

    def _arguments(self, action: str, extra: list[str] | None = None):
        argv = [action, "--device", self.target]
        if extra:
            argv.extend(extra)
        return transport.parse_arguments(argv)

    def _ready(self) -> dict[str, Any] | None:
        try:
            found = transport.read_ready_state(self._arguments("snapshot"), fresh=True)
        except (OSError, RuntimeError, ValueError, json.JSONDecodeError):
            return None
        return found if isinstance(found, dict) else None

    def scoped(self) -> list[int]:
        return [pid for pid, _ in transport.scoped_processes()]

    def _record(self) -> dict[str, Any] | None:
        path = self.root / SESSION_RECORD
        if not path.is_file():
            return None
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        return record if isinstance(record, dict) else None

    def _remember(self, pid: int, session: str) -> None:
        path = self.root / SESSION_RECORD
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"pid": pid, "sessionID": session}), encoding="utf-8"
        )

    def _forget_record(self) -> None:
        path = self.root / SESSION_RECORD
        if path.is_file():
            path.unlink()

    def alive(self) -> bool:
        if not self.session_ready or self.ready is None:
            return False
        record = self._record()
        if record is None:
            self._forget()
            return False
        if record.get("sessionID") != self.ready.get("sessionID"):
            self._forget()
            return False
        if int(record.get("pid", -1)) not in self.scoped():
            self._forget()
            return False
        found = self._ready()
        if found is None or found.get("sessionID") != self.ready.get("sessionID"):
            self._forget()
            return False
        return True

    def _forget(self) -> None:
        self.session_ready = False
        self.ready = None

    def halt(self) -> int:
        terminated = 0
        for pid in self.scoped():
            subprocess.run(["kill", "-TERM", str(pid)], capture_output=True)
            terminated += 1
        container = self._container()
        if container is not None:
            stale = container / CHANNEL_ROOT / "ready.json"
            if stale.exists():
                stale.unlink()
        self._forget()
        self._forget_record()
        return terminated

    def _container(self) -> Path | None:
        completed = subprocess.run(
            [
                "xcrun",
                "simctl",
                "get_app_container",
                self.target,
                RUNNER_BUNDLE,
                "data",
            ],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            return None
        return Path(completed.stdout.strip())

    def ensure_session(self, lane: str) -> tuple[dict[str, Any], bool, str]:
        if self.alive():
            return {"lane": lane, "reused": True, "ready": self.ready}, True, "session already held"
        record = self._record()
        if record is not None and int(record.get("pid", -1)) in self.scoped():
            found = self._ready()
            if found is not None and found.get("sessionID") == record.get("sessionID"):
                self.ready = found
                self.session_ready = True
                return {"lane": lane, "reused": True, "ready": found}, True, "session adopted"
        self.halt()
        spec = self._runner_spec()
        if spec is None:
            return {"lane": lane, "reused": False}, False, "no test bundle; build for testing first"
        self.runner = self._launch(spec)
        deadline = time.monotonic() + READY_TIMEOUT
        while time.monotonic() < deadline:
            found = self._ready()
            if found is not None:
                self.ready = found
                self.session_ready = True
                if self.runner is not None:
                    self._remember(self.runner.pid, str(found.get("sessionID")))
                return {"lane": lane, "reused": False, "ready": found}, True, "session started"
            if self.runner.poll() is not None:
                return {"lane": lane, "reused": False}, False, "the runner exited before publishing a session"
            time.sleep(0.25)
        return {"lane": lane, "reused": False}, False, f"the runner published no session within {READY_TIMEOUT:.0f} s"

    def _runner_spec(self) -> Path | None:
        products = self.root / BUILD_PRODUCTS
        if not products.is_dir():
            return None
        matches = sorted(products.glob(f"*{RUNNER_SPEC}*.xctestrun"))
        return matches[0] if matches else None

    def _launch(self, spec: Path) -> subprocess.Popen:
        log = self.root / ".console" / "runner.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        handle = log.open("a", encoding="utf-8")
        return subprocess.Popen(
            [
                "xcodebuild",
                "test-without-building",
                "-xctestrun",
                str(spec),
                "-destination",
                f"platform=visionOS Simulator,id={self.target}",
                "-parallel-testing-enabled",
                "NO",
            ],
            cwd=str(self.root),
            stdout=handle,
            stderr=handle,
            start_new_session=True,
        )

    def invoke(
        self, action: str, identifier: str | None, text: str | None
    ) -> tuple[dict[str, Any], bool, str]:
        if not self.alive():
            return {}, False, "the session is gone; ensure it again"
        extra: list[str] = []
        if identifier is not None:
            extra.extend(["--identifier", identifier])
        if text is not None:
            extra.extend(["--text", text])
        answer = transport.send_command(self._arguments(action, extra))
        ok = bool(answer.get("success", False))
        detail = str(answer.get("message") or answer.get("error") or f"{action} answered")
        return answer, ok, detail

class Server:
    def __init__(self, root: Path, target: str) -> None:
        self.root = root
        self.lock = threading.Lock()
        self.channel = Channel(root, target)
        self.started = time.time()
        self.last_request = self.started

    def serve(self) -> None:
        path = socket_path(self.root)
        path.parent.mkdir(parents=True, exist_ok=True)
        if request(self.root, {"op": "ping"}, timeout=2).get("kind") == "result":
            return
        if path.exists():
            path.unlink()
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        server.listen(8)
        path.chmod(0o600)
        state_path(self.root).write_text(
            json.dumps({"pid": os.getpid(), "started": self.started, "target": self.channel.target}),
            encoding="utf-8",
        )
        server.settimeout(5.0)
        try:
            self._accept(server)
        finally:
            self.channel.halt()
            server.close()
            for leftover in (path, state_path(self.root)):
                if leftover.exists():
                    leftover.unlink()

    def _accept(self, server: socket.socket) -> None:
        while True:
            if time.time() - self.last_request > IDLE_EXIT_SECONDS:
                return
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            self.last_request = time.time()
            with connection:
                self._serve_one(connection)
            self.last_request = time.time()

    def _serve_one(self, connection: socket.socket) -> None:
        buffer = b""
        while b"\n" not in buffer:
            chunk = connection.recv(65536)
            if not chunk:
                return
            buffer += chunk
        request = json.loads(buffer.split(b"\n", 1)[0])
        with self.lock:
            response = self._handle(request)
        connection.sendall(json.dumps(response).encode() + b"\n")

    def _handle(self, request: dict[str, Any]) -> dict[str, Any]:
        operation = request.get("op")
        if operation == "ping":
            return {"kind": "result", "value": {"pid": os.getpid()}}
        if operation == "stop":
            self.started = -1e12
            return {"kind": "result", "value": {"stopped": True}}
        if operation == "ensure":
            payload, ok, detail = self.channel.ensure_session(request.get("lane", "simulator"))
            return {"kind": "result", "value": {"ok": ok, "detail": detail, "payload": payload}}
        if operation == "invoke":
            payload, ok, detail = self.channel.invoke(
                request.get("action", "snapshot"),
                request.get("identifier"),
                request.get("text"),
            )
            return {"kind": "result", "value": {"ok": ok, "detail": detail, "payload": payload}}
        return {"kind": "error", "message": f"unknown op {operation!r}"}


def request(root: Path, payload: dict[str, Any], timeout: float = 1200) -> dict[str, Any]:
    path = socket_path(root)
    if not path.exists():
        return {"kind": "error", "message": "no daemon socket"}
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        client.connect(str(path))
        client.sendall(json.dumps(payload).encode() + b"\n")
        buffer = b""
        while b"\n" not in buffer:
            chunk = client.recv(65536)
            if not chunk:
                break
            buffer += chunk
        return json.loads(buffer.split(b"\n", 1)[0]) if buffer else {"kind": "error", "message": "empty"}
    except OSError as error:
        return {"kind": "error", "message": str(error)}
    finally:
        client.close()


def spawn(root: Path, targets: str) -> None:
    directory = root / ".console"
    directory.mkdir(parents=True, exist_ok=True)
    lock = directory / "launch.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.close(descriptor)
    except OSError:
        pass
    try:
        with (directory / "daemon.log").open("a", encoding="utf-8") as log:
            subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "--serve", "--root", str(root), "--target", targets],
                stdout=log,
                stderr=log,
                start_new_session=True,
                cwd=str(root),
            )
        deadline = time.time() + 30
        while time.time() < deadline:
            if socket_path(root).exists():
                return
            time.sleep(0.05)
    finally:
        if lock.exists():
            lock.unlink()


def ensure_running(root: Path, target: str) -> bool:
    if request(root, {"op": "ping"}, timeout=2).get("kind") == "result":
        return True
    spawn(root, target)
    deadline = time.time() + START_DEADLINE_SECONDS
    while time.time() < deadline:
        if request(root, {"op": "ping"}, timeout=2).get("kind") == "result":
            return True
        time.sleep(0.2)
    return False


def main(argv: list[str]) -> int:
    if "--serve" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
        target = argv[argv.index("--target") + 1]
        Server(root, target).serve()
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
