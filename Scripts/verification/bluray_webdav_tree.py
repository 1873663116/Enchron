"""Closed, read-only WebDAV path tree for the registered Blu-ray corpus."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath


REGISTRY = Path(__file__).resolve().parents[2] / "Tests/Fixtures/bluray-disc-registry.json"
VIRTUAL_ROOT = "DiscImages"


class BluRayWebDAVTree:
    def __init__(self, source_root: Path, registry_path: Path = REGISTRY) -> None:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
        if registry.get("schemaVersion") != 1 or not isinstance(registry.get("discs"), list):
            raise ValueError("Blu-ray WebDAV registry is invalid")
        root = source_root.resolve()
        self.files: dict[str, Path] = {}
        self.directories: set[str] = {VIRTUAL_ROOT}
        for entry in registry["discs"]:
            relative = entry.get("relativePath")
            if not isinstance(relative, str) or "\\" in relative:
                raise ValueError("Blu-ray WebDAV registry path is invalid")
            path = PurePosixPath(relative)
            if path.is_absolute() or ".." in path.parts or path.parts[:2] != ("Samples", "DiscImages"):
                raise ValueError("Blu-ray WebDAV path escapes registered DiscImages")
            source = root.joinpath(*path.parts).resolve()
            if not source.is_relative_to(root):
                raise ValueError("Blu-ray WebDAV source escapes sourceRoot")
            virtual = PurePosixPath(VIRTUAL_ROOT, *path.parts[2:])
            if entry.get("kind") == "iso":
                if not source.is_file() or source.is_symlink():
                    raise ValueError(f"Registered Blu-ray ISO is unavailable: {source}")
                self._add_file(virtual, source)
            elif entry.get("kind") == "directory":
                if not source.is_dir() or source.is_symlink() or not (source / "BDMV/index.bdmv").is_file():
                    raise ValueError(f"Registered Blu-ray directory is unavailable: {source}")
                self._add_directory(virtual)
                for item in source.rglob("*"):
                    if item.is_symlink():
                        raise ValueError(f"Registered Blu-ray directory contains a symlink: {item}")
                    member = virtual.joinpath(*item.relative_to(source).parts)
                    if item.is_dir():
                        self._add_directory(member)
                    elif item.is_file():
                        self._add_file(member, item)
            else:
                raise ValueError("Blu-ray WebDAV registry kind is invalid")

    def _add_directory(self, path: PurePosixPath) -> None:
        parts = path.parts
        for index in range(1, len(parts) + 1):
            self.directories.add(PurePosixPath(*parts[:index]).as_posix())

    def _add_file(self, path: PurePosixPath, source: Path) -> None:
        key = path.as_posix()
        if key in self.files:
            raise ValueError(f"Blu-ray WebDAV path is duplicated: {key}")
        self._add_directory(path.parent)
        self.files[key] = source

    def children(self, directory: str) -> list[str]:
        if directory not in self.directories:
            raise KeyError(directory)
        prefix = directory + "/"
        return sorted({
            prefix + rest.split("/", 1)[0]
            for path in self.files.keys() | self.directories
            if path.startswith(prefix)
            for rest in [path[len(prefix):]]
            if rest
        })

    def file(self, path: str) -> Path | None:
        return self.files.get(path)

    def contains(self, path: str) -> bool:
        return path in self.directories or path in self.files
