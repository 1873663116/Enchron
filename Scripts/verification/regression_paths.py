from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_ROOT = REPOSITORY_ROOT.parent
TEST_SERVICES_ROOT = WORKSPACE_ROOT / "test-services"
REPOSITORY_SCHEME = "repo://"
WORKSPACE_SCHEME = "workspace://"


class PortableReferenceError(ValueError):
    pass


def reference(path: Path) -> str:
    candidate = Path(path)
    for base, scheme in ((REPOSITORY_ROOT, REPOSITORY_SCHEME), (WORKSPACE_ROOT, WORKSPACE_SCHEME)):
        for shape in (candidate, candidate.resolve()):
            try:
                relative = shape.relative_to(base)
            except ValueError:
                continue
            return scheme + relative.as_posix()
    raise PortableReferenceError(
        f"{path} is outside the repository and its workspace, so no portable reference names it"
    )


def is_reference(text: str) -> bool:
    return text.startswith(REPOSITORY_SCHEME) or text.startswith(WORKSPACE_SCHEME)


def resolve(text: str) -> Path:
    if text.startswith(REPOSITORY_SCHEME):
        relative = text[len(REPOSITORY_SCHEME):]
        base = REPOSITORY_ROOT
    elif text.startswith(WORKSPACE_SCHEME):
        relative = text[len(WORKSPACE_SCHEME):]
        base = WORKSPACE_ROOT
    else:
        path = Path(text)
        if not path.is_absolute():
            raise PortableReferenceError(
                f"{text!r} is neither a repo:// or workspace:// reference nor an absolute path"
            )
        return path
    if not relative or relative.startswith("/") or ".." in relative.split("/"):
        raise PortableReferenceError(f"{text!r} carries an empty, absolute, or escaping remainder")
    return base / relative
