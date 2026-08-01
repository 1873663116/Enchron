#!/usr/bin/env python3

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import subprocess


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE_PREFIX = "docs/acceptance/evidence/"


def run(*command: str) -> str:
    return subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout.strip()


def digest_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repository_files(
    repository_root: pathlib.Path = REPOSITORY_ROOT,
) -> list[pathlib.Path]:
    output = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=repository_root,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    paths = []
    for raw_path in output.split(b"\0"):
        if not raw_path:
            continue
        relative_path = pathlib.Path(os.fsdecode(raw_path))
        if relative_path.as_posix().startswith(EVIDENCE_PREFIX):
            continue
        paths.append(relative_path)
    return sorted(set(paths), key=lambda path: path.as_posix())


def capture_tree(
    repository_root: pathlib.Path = REPOSITORY_ROOT,
) -> tuple[str, list[dict[str, object]]]:
    aggregate = hashlib.sha256()
    entries = []
    for relative_path in repository_files(repository_root):
        absolute_path = repository_root / relative_path
        if absolute_path.is_symlink():
            kind = "symlink"
            content_digest = hashlib.sha256(os.readlink(absolute_path).encode()).hexdigest()
            size = len(os.readlink(absolute_path).encode())
        elif absolute_path.is_file():
            kind = "file"
            content_digest = digest_file(absolute_path)
            size = absolute_path.stat().st_size
        else:
            kind = "deleted"
            content_digest = "-"
            size = 0
        canonical = f"{kind}\0{relative_path.as_posix()}\0{size}\0{content_digest}\n"
        aggregate.update(canonical.encode())
        entries.append(
            {
                "path": relative_path.as_posix(),
                "kind": kind,
                "bytes": size,
                "sha256": content_digest,
            }
        )
    return aggregate.hexdigest(), entries


def capture_artifact(path_value: str) -> dict[str, object]:
    path = pathlib.Path(path_value).resolve()
    if not path.exists():
        raise FileNotFoundError(f"Validation artifact does not exist: {path}")
    aggregate = hashlib.sha256()
    file_count = 0
    byte_count = 0
    files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
    for file_path in files:
        relative_path = file_path.name if path.is_file() else file_path.relative_to(path).as_posix()
        content_digest = digest_file(file_path)
        size = file_path.stat().st_size
        aggregate.update(f"{relative_path}\0{size}\0{content_digest}\n".encode())
        file_count += 1
        byte_count += size
    return {
        "path": str(path),
        "files": file_count,
        "bytes": byte_count,
        "sha256": aggregate.hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bind Enchron validation evidence to an exact dirty or clean working tree."
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("--artifact", action="append", default=[])
    parser.add_argument("--result", action="append", default=[])
    parser.add_argument("--command", action="append", default=[])
    arguments = parser.parse_args()

    tree_identity, entries = capture_tree()
    manifest = {
        "schemaVersion": 1,
        "capturedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "repository": str(REPOSITORY_ROOT),
        "git": {
            "head": run("git", "rev-parse", "HEAD"),
            "status": run("git", "status", "--short"),
        },
        "productTree": {
            "identityAlgorithm": "sha256 of sorted kind, path, byte count, and file sha256 records",
            "excludedPrefix": EVIDENCE_PREFIX,
            "sha256": tree_identity,
            "files": entries,
        },
        "toolchain": {
            "xcode": run("xcodebuild", "-version"),
            "swift": run("swift", "--version"),
            "os": run("sw_vers"),
        },
        "results": arguments.result,
        "commands": arguments.command,
        "artifacts": [capture_artifact(path) for path in arguments.artifact],
    }

    output_path = pathlib.Path(arguments.output)
    if not output_path.is_absolute():
        output_path = REPOSITORY_ROOT / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"tree_sha256={tree_identity}")
    print(f"manifest={output_path}")


if __name__ == "__main__":
    main()
