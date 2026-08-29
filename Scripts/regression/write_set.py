from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import PurePosixPath


class WriteSetError(ValueError):
    pass


@dataclass(frozen=True, order=True)
class WriteScope:
    path: str
    subtree: bool

    @classmethod
    def parse(cls, raw: object) -> "WriteScope":
        if not isinstance(raw, str) or not raw.strip():
            raise WriteSetError("write scope must be a nonempty string")
        value = raw.strip()
        subtree = value.endswith("/**")
        path = value[:-3].rstrip("/") if subtree else value.rstrip("/")
        if not path or path in (".", "./"):
            raise WriteSetError("repository-wide write scopes are forbidden")
        if "*" in path or "?" in path or "[" in path:
            raise WriteSetError(f"unsupported write-scope pattern: {value}")
        candidate = PurePosixPath(path)
        if candidate.is_absolute() or ".." in candidate.parts:
            raise WriteSetError(f"write scope must be repository-relative: {value}")
        normalized = candidate.as_posix()
        if normalized.startswith("./"):
            normalized = normalized[2:]
        return cls(normalized, subtree)

    def contains(self, path: str) -> bool:
        return path == self.path or self.subtree and path.startswith(self.path + "/")

    def overlaps(self, other: "WriteScope") -> bool:
        if self.path == other.path:
            return True
        if self.subtree and other.path.startswith(self.path + "/"):
            return True
        if other.subtree and self.path.startswith(other.path + "/"):
            return True
        return False

    def render(self) -> str:
        return self.path + ("/**" if self.subtree else "")


@dataclass(frozen=True)
class WriteTask:
    identifier: str
    dependencies: tuple[str, ...]
    writes: tuple[WriteScope, ...]


@dataclass(frozen=True)
class WriteConflict:
    first_task: str
    first_scope: str
    second_task: str
    second_scope: str


@dataclass(frozen=True)
class WritePlan:
    tasks: tuple[WriteTask, ...]

    @classmethod
    def parse(cls, payload: object) -> "WritePlan":
        if not isinstance(payload, dict) or payload.get("version") != 1:
            raise WriteSetError("write plan must be a version 1 object")
        entries = payload.get("tasks")
        if not isinstance(entries, list) or not entries:
            raise WriteSetError("write plan must contain tasks")
        tasks: list[WriteTask] = []
        seen: set[str] = set()
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                raise WriteSetError(f"tasks[{index}] must be an object")
            identifier = entry.get("id")
            if not isinstance(identifier, str) or not identifier.strip():
                raise WriteSetError(f"tasks[{index}].id must be nonempty")
            if identifier in seen:
                raise WriteSetError(f"duplicate task id: {identifier}")
            seen.add(identifier)
            dependencies = entry.get("dependsOn", [])
            writes = entry.get("writes")
            if not isinstance(dependencies, list) or not all(
                isinstance(item, str) and item for item in dependencies
            ):
                raise WriteSetError(f"{identifier}.dependsOn must be a string list")
            if not isinstance(writes, list) or not writes:
                raise WriteSetError(f"{identifier}.writes must be nonempty")
            scopes = tuple(sorted({WriteScope.parse(item) for item in writes}))
            tasks.append(WriteTask(identifier, tuple(sorted(set(dependencies))), scopes))
        plan = cls(tuple(sorted(tasks, key=lambda item: item.identifier)))
        plan._validate_graph()
        return plan

    def _validate_graph(self) -> None:
        identifiers = {task.identifier for task in self.tasks}
        for task in self.tasks:
            missing = set(task.dependencies) - identifiers
            if missing:
                raise WriteSetError(
                    f"{task.identifier} depends on unknown tasks: {', '.join(sorted(missing))}"
                )
            if task.identifier in task.dependencies:
                raise WriteSetError(f"{task.identifier} cannot depend on itself")
        visiting: set[str] = set()
        visited: set[str] = set()
        dependencies = {task.identifier: task.dependencies for task in self.tasks}

        def visit(identifier: str) -> None:
            if identifier in visiting:
                raise WriteSetError(f"write plan dependency cycle reaches {identifier}")
            if identifier in visited:
                return
            visiting.add(identifier)
            for dependency in dependencies[identifier]:
                visit(dependency)
            visiting.remove(identifier)
            visited.add(identifier)

        for identifier in sorted(identifiers):
            visit(identifier)

    def ancestors(self, identifier: str) -> set[str]:
        dependencies = {task.identifier: task.dependencies for task in self.tasks}
        found: set[str] = set()
        pending = list(dependencies[identifier])
        while pending:
            candidate = pending.pop()
            if candidate in found:
                continue
            found.add(candidate)
            pending.extend(dependencies[candidate])
        return found

    def conflicts(self) -> tuple[WriteConflict, ...]:
        conflicts: list[WriteConflict] = []
        ancestry = {task.identifier: self.ancestors(task.identifier) for task in self.tasks}
        for index, first in enumerate(self.tasks):
            for second in self.tasks[index + 1 :]:
                ordered = (
                    first.identifier in ancestry[second.identifier]
                    or second.identifier in ancestry[first.identifier]
                )
                if ordered:
                    continue
                for first_scope in first.writes:
                    for second_scope in second.writes:
                        if first_scope.overlaps(second_scope):
                            conflicts.append(
                                WriteConflict(
                                    first.identifier,
                                    first_scope.render(),
                                    second.identifier,
                                    second_scope.render(),
                                )
                            )
        return tuple(conflicts)

    def canonical_payload(self) -> dict[str, object]:
        return {
            "version": 1,
            "tasks": [
                {
                    "id": task.identifier,
                    "dependsOn": list(task.dependencies),
                    "writes": [scope.render() for scope in task.writes],
                }
                for task in self.tasks
            ],
        }

    def digest(self) -> str:
        encoded = json.dumps(
            self.canonical_payload(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return "sha256:" + hashlib.sha256(encoded).hexdigest()


def report(plan: WritePlan) -> dict[str, object]:
    conflicts = plan.conflicts()
    return {
        "version": 1,
        "planDigest": plan.digest(),
        "taskCount": len(plan.tasks),
        "conflicts": [
            {
                "firstTask": conflict.first_task,
                "firstScope": conflict.first_scope,
                "secondTask": conflict.second_task,
                "secondScope": conflict.second_scope,
            }
            for conflict in conflicts
        ],
        "safe": not conflicts,
    }


def parse_json_bytes(encoded: bytes) -> WritePlan:
    try:
        payload = json.loads(encoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise WriteSetError(f"write plan is not valid JSON: {error}") from error
    return WritePlan.parse(payload)
