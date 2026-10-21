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
from vocab import VERBS


CHANNEL_SCRIPT = Path("Scripts/verification/interactive_visionpro_ui.py")
IDLE_EXIT_SECONDS = 900.0
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
        self.runner: subprocess.Popen | None = None
        self.ready: dict[str, Any] | None = None

    def ensure_session(self, lane: str) -> tuple[dict[str, Any], bool, str]:
        if self.alive():
            return {"lane": lane, "reused": True, "ready": self.ready}, True, "session already held"
        found = self._read_ready() if self.runner_processes() > 0 else None
        if found is not None:
            self.ready = found
            self.session_ready = True
            return {"lane": lane, "reused": True, "ready": found}, True, "session adopted"
        started = self._launch_runner()
        if not started:
            return {"lane": lane}, False, "the runner could not be launched; build for testing first"
        ready = self._await_ready()
        if ready is None:
            return {"lane": lane}, False, f"the runner did not publish a session within {READY_TIMEOUT_SECONDS:.0f} s"
        self.ready = ready
        self.session_ready = True
        return {"lane": lane, "reused": False, "ready": ready}, True, "session started"

    def _runner_spec(self) -> Path | None:
        products = self.root / BUILD_PRODUCTS
        if not products.is_dir():
            return None
        matches = sorted(products.glob(f"*{RUNNER_SPEC}*.xctestrun"))
        return matches[0] if matches else None

    def _clear_stale(self) -> None:
        container = self._container()
        if container is not None:
            stale = container / CHANNEL_ROOT / "ready.json"
            if stale.exists():
                stale.unlink()
        mine = self.runner.pid if self.runner is not None else None
        for process in self._runner_pids():
            if process != mine:
                subprocess.run(["kill", "-TERM", str(process)], capture_output=True)

    def _runner_pids(self) -> list[int]:
        completed = subprocess.run(
            ["pgrep", "-f", "xcodebuild test-without-building"],
            capture_output=True,
            text=True,
        )
        return [
            int(line)
            for line in completed.stdout.split()
            if line.strip().isdigit()
        ]

    def _launch_runner(self) -> bool:
        spec = self._runner_spec()
        if spec is None:
            return False
        self._clear_stale()
        log = self.root / ".console" / "runner.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        handle = log.open("a", encoding="utf-8")
        self.runner = subprocess.Popen(
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
        return True

    def _container(self) -> Path | None:
        completed = subprocess.run(
            [
                "xcrun",
                "simctl",
                "get_app_container",
                self.target,
                "com.xiongzhipeng.EnchronAppUITests.xctrunner",
                "data",
            ],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            return None
        return Path(completed.stdout.strip())

    def runner_processes(self) -> int:
        completed = subprocess.run(
            ["ps", "-ax", "-o", "command"],
            capture_output=True,
            text=True,
        )
        return sum(
            1
            for line in completed.stdout.splitlines()
            if "xcodebuild test-without-building" in line
        )

    def alive(self) -> bool:
        if not self.session_ready:
            return False
        if self.runner is not None and self.runner.poll() is not None:
            self.session_ready = False
            self.ready = None
            return False
        if self.runner is None and self.runner_processes() == 0:
            self.session_ready = False
            self.ready = None
            return False
        found = self._read_ready()
        if found is None:
            self.session_ready = False
            self.ready = None
            return False
        if self.ready is not None and found.get("sessionID") != self.ready.get("sessionID"):
            self.session_ready = False
            self.ready = None
            return False
        return True

    def _read_ready(self) -> dict[str, Any] | None:
        container = self._container()
        if container is None:
            return None
        candidate = container / CHANNEL_ROOT / "ready.json"
        if not candidate.exists():
            return None
        try:
            return json.loads(candidate.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return None

    def _await_ready(self) -> dict[str, Any] | None:
        deadline = time.time() + READY_TIMEOUT_SECONDS
        while time.time() < deadline:
            found = self._read_ready()
            if found is not None:
                return found
            if self.runner is not None and self.runner.poll() is not None:
                return None
            time.sleep(0.25)
        return None

    def invoke(
        self, action: str, identifier: str | None, text: str | None
    ) -> tuple[dict[str, Any], bool, str]:
        if not self.alive():
            return {}, False, "the session is gone; ensure it again"
        arguments = ["--device", self.target, action]
        if identifier:
            arguments.extend(["--identifier", identifier])
        if text:
            arguments.extend(["--text", text])
        return self._invoke(arguments)

    def _invoke(self, arguments: list[str]) -> tuple[dict[str, Any], bool, str]:
        completed = subprocess.run(
            [sys.executable, str(self.root / CHANNEL_SCRIPT), *arguments],
            capture_output=True,
            text=True,
            timeout=1200,
            cwd=str(self.root),
        )
        try:
            payload = json.loads(completed.stdout) if completed.stdout.strip() else {}
        except json.JSONDecodeError:
            payload = {"raw": completed.stdout[-4000:]}
        ok = completed.returncode == 0 and bool(payload.get("success", True))
        return payload, ok, f"{' '.join(arguments[:2])} exited {completed.returncode}"

    def halt(self) -> None:
        if not self.session_ready:
            return
        subprocess.run(
            [sys.executable, str(self.root / CHANNEL_SCRIPT), "halt", "--device", self.target],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=str(self.root),
        )
        self.session_ready = False


class Server:
    def __init__(self, root: Path, target: str) -> None:
        self.root = root
        self.lock = threading.Lock()
        self.channel = Channel(root, target)
        self.started = time.time()

    def serve(self) -> None:
        path = socket_path(self.root)
        path.parent.mkdir(parents=True, exist_ok=True)
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
            if time.time() - self.started > IDLE_EXIT_SECONDS:
                return
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            with connection:
                self._serve_one(connection)

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
    answer = request(root, {"op": "ping"}, timeout=2)
    if answer.get("kind") == "result":
        return True
    spawn(root, target)
    return request(root, {"op": "ping"}, timeout=5).get("kind") == "result"


def main(argv: list[str]) -> int:
    if "--serve" in argv:
        root = Path(argv[argv.index("--root") + 1]).resolve()
        target = argv[argv.index("--target") + 1]
        Server(root, target).serve()
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
