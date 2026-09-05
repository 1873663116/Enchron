#!/usr/bin/env python3

from __future__ import annotations

import ast
from pathlib import Path
import sys
from typing import Dict, List, Optional, Sequence, Set, Tuple


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REGRESSION_ROOT = REPOSITORY_ROOT / "Scripts/regression"
CORE_ROOT = REGRESSION_ROOT / "core"

ALLOWED_INTERNAL_IMPORTS = {
    "__init__": frozenset(("errors",)),
    "errors": frozenset(),
    "fields": frozenset(),
    "ids": frozenset(("errors",)),
    "digest": frozenset(("ids",)),
    "frontmatter": frozenset(("digest", "errors", "ids")),
    "expression": frozenset(("errors", "ids")),
    "applicability": frozenset(("digest", "errors", "ids")),
    "contracts": frozenset(
        ("applicability", "digest", "errors", "expression", "ids")
    ),
    "state": frozenset(("contracts", "errors", "ids")),
    "scheduler": frozenset(("contracts", "errors", "ids")),
    "capability": frozenset(("contracts", "digest", "errors", "ids")),
    "review": frozenset(("digest", "errors", "ids")),
    "review_catalog": frozenset(("contracts", "errors", "review")),
    "catalog": frozenset(
        (
            "applicability",
            "contracts",
            "digest",
            "errors",
            "expression",
            "frontmatter",
            "ids",
        )
    ),
    "events": frozenset(
        ("capability", "contracts", "digest", "errors", "expression", "ids", "state")
    ),
    "store": frozenset(("digest", "errors", "ids")),
    "ledger": frozenset(
        ("contracts", "digest", "errors", "events", "ids", "replay", "store")
    ),
    "runview": frozenset(
        (
            "capability",
            "contracts",
            "digest",
            "errors",
            "events",
            "expression",
            "fields",
            "ids",
            "state",
        )
    ),
    "replay": frozenset(
        (
            "contracts",
            "digest",
            "errors",
            "events",
            "expression",
            "ids",
            "ledger",
            "runview",
            "state",
        )
    ),
    "plan": frozenset(
        (
            "applicability",
            "capability",
            "catalog",
            "contracts",
            "digest",
            "errors",
            "expression",
            "ids",
            "scheduler",
            "state",
        )
    ),
    "compiler": frozenset(
        (
            "applicability",
            "capability",
            "catalog",
            "contracts",
            "digest",
            "errors",
            "expression",
            "ids",
            "plan",
            "review",
            "review_catalog",
            "scheduler",
            "state",
        )
    ),
    "runtime": frozenset(
        (
            "capability",
            "compiler",
            "contracts",
            "digest",
            "errors",
            "events",
            "expression",
            "ids",
            "ledger",
            "plan",
            "replay",
            "runview",
            "scheduler",
            "state",
            "store",
        )
    ),
}

PYTHON_3_9_STDLIB_ROOTS_ALL_PLATFORMS = frozenset(
    (
        "__future__",
        "_thread",
        "abc",
        "aifc",
        "argparse",
        "array",
        "ast",
        "asynchat",
        "asyncio",
        "asyncore",
        "atexit",
        "audioop",
        "base64",
        "bdb",
        "binascii",
        "binhex",
        "bisect",
        "builtins",
        "bz2",
        "calendar",
        "cgi",
        "cgitb",
        "chunk",
        "cmath",
        "cmd",
        "code",
        "codecs",
        "codeop",
        "collections",
        "colorsys",
        "compileall",
        "concurrent",
        "configparser",
        "contextlib",
        "contextvars",
        "copy",
        "copyreg",
        "crypt",
        "csv",
        "ctypes",
        "curses",
        "dataclasses",
        "datetime",
        "dbm",
        "decimal",
        "difflib",
        "dis",
        "distutils",
        "doctest",
        "email",
        "encodings",
        "ensurepip",
        "enum",
        "errno",
        "faulthandler",
        "fcntl",
        "filecmp",
        "fileinput",
        "fnmatch",
        "fractions",
        "ftplib",
        "functools",
        "gc",
        "getopt",
        "getpass",
        "gettext",
        "glob",
        "graphlib",
        "grp",
        "gzip",
        "hashlib",
        "heapq",
        "hmac",
        "html",
        "http",
        "imaplib",
        "imghdr",
        "imp",
        "importlib",
        "inspect",
        "io",
        "ipaddress",
        "itertools",
        "json",
        "keyword",
        "lib2to3",
        "linecache",
        "locale",
        "logging",
        "lzma",
        "mailbox",
        "mailcap",
        "marshal",
        "math",
        "mimetypes",
        "mmap",
        "modulefinder",
        "msilib",
        "msvcrt",
        "multiprocessing",
        "netrc",
        "nis",
        "nntplib",
        "numbers",
        "operator",
        "optparse",
        "os",
        "ossaudiodev",
        "parser",
        "pathlib",
        "pdb",
        "pickle",
        "pickletools",
        "pipes",
        "pkgutil",
        "platform",
        "plistlib",
        "poplib",
        "posix",
        "pprint",
        "profile",
        "pstats",
        "pty",
        "pwd",
        "py_compile",
        "pyclbr",
        "pydoc",
        "queue",
        "quopri",
        "random",
        "re",
        "readline",
        "reprlib",
        "resource",
        "rlcompleter",
        "runpy",
        "sched",
        "secrets",
        "select",
        "selectors",
        "shelve",
        "shlex",
        "shutil",
        "signal",
        "site",
        "smtpd",
        "smtplib",
        "sndhdr",
        "socket",
        "socketserver",
        "spwd",
        "sqlite3",
        "ssl",
        "stat",
        "statistics",
        "string",
        "stringprep",
        "struct",
        "subprocess",
        "sunau",
        "symbol",
        "symtable",
        "sys",
        "sysconfig",
        "syslog",
        "tabnanny",
        "tarfile",
        "telnetlib",
        "tempfile",
        "termios",
        "textwrap",
        "threading",
        "time",
        "timeit",
        "tkinter",
        "token",
        "tokenize",
        "trace",
        "traceback",
        "tracemalloc",
        "tty",
        "turtle",
        "turtledemo",
        "types",
        "typing",
        "unicodedata",
        "unittest",
        "urllib",
        "uu",
        "uuid",
        "venv",
        "warnings",
        "wave",
        "weakref",
        "webbrowser",
        "winreg",
        "winsound",
        "wsgiref",
        "xdrlib",
        "xml",
        "xmlrpc",
        "zipapp",
        "zipfile",
        "zipimport",
        "zlib",
        "zoneinfo",
    )
)

PUBLIC_ADAPTER_CORE_MODULES = frozenset(("contracts", "digest", "ids"))
CORE_PREFIXES = ("Scripts.regression.core", "regression.core", "core")
FORBIDDEN_CORE_PREFIXES = (
    "Scripts.verification",
    "Scripts.regression.operations",
    "Scripts.regression.oracles",
    "regression.operations",
    "regression.oracles",
)


def _module_name(path: Path, root: Path) -> str:
    relative = path.relative_to(root).with_suffix("")
    if relative.name == "__init__":
        return ".".join(relative.parts[:-1]) or "__init__"
    return ".".join(relative.parts)


def _diagnostic(path: str, line: int, rule: str, message: str) -> str:
    location = f"{path}:{line}" if line else path
    return f"{location}: error: [{rule}] {message}"


def _matches_prefix(module: str, prefix: str) -> bool:
    return module == prefix or module.startswith(prefix + ".")


def _absolute_core_target(module: str) -> Optional[str]:
    for prefix in CORE_PREFIXES:
        if module.startswith(prefix + "."):
            return module[len(prefix) + 1 :].split(".", 1)[0]
        if module == prefix:
            return "core"
    return None


def _forbidden_core_import(module: str) -> bool:
    return any(_matches_prefix(module, prefix) for prefix in FORBIDDEN_CORE_PREFIXES)


def _from_candidates(node: ast.ImportFrom) -> Tuple[str, ...]:
    module = node.module or ""
    if node.level:
        dots = "." * node.level
        if module:
            return (dots + module,)
        return tuple(dots + alias.name for alias in node.names)

    package_parents = frozenset(("Scripts", "Scripts.regression", "regression"))
    if module in package_parents:
        return tuple(module + "." + alias.name for alias in node.names)
    if module in CORE_PREFIXES:
        return tuple(module + "." + alias.name for alias in node.names)
    return (module,)


def _relative_core_target(candidate: str) -> Optional[str]:
    stripped = candidate.lstrip(".")
    level = len(candidate) - len(stripped)
    if level == 1 and stripped:
        return stripped.split(".", 1)[0]
    return None


def _classify_core_candidate(
    source_module: str,
    candidate: str,
    path: str,
    line: int,
) -> Tuple[List[str], Optional[str]]:
    violations: List[str] = []
    target = _relative_core_target(candidate)
    display = candidate

    if target is None and candidate.startswith(".."):
        violations.append(
            _diagnostic(
                path,
                line,
                "forbidden-core-import",
                f"core module '{source_module}' imports '{display}'",
            )
        )
        return violations, None

    if target is None:
        if _forbidden_core_import(candidate):
            violations.append(
                _diagnostic(
                    path,
                    line,
                    "forbidden-core-import",
                    f"core module '{source_module}' imports '{display}'",
                )
            )
            return violations, None
        target = _absolute_core_target(candidate)

    if target is not None:
        if target == "core":
            violations.append(
                _diagnostic(
                    path,
                    line,
                    "undeclared-core-import",
                    f"core module '{source_module}' may not import the core package",
                )
            )
            return violations, None
        if target not in ALLOWED_INTERNAL_IMPORTS.get(source_module, frozenset()):
            violations.append(
                _diagnostic(
                    path,
                    line,
                    "undeclared-core-import",
                    f"core module '{source_module}' may not import core module '{target}'",
                )
            )
        return violations, target

    root = candidate.split(".", 1)[0]
    if root not in PYTHON_3_9_STDLIB_ROOTS_ALL_PLATFORMS:
        violations.append(
            _diagnostic(
                path,
                line,
                "non-stdlib-import",
                f"core module '{source_module}' imports non-stdlib module '{candidate}'",
            )
        )
    return violations, None


def _core_imports(
    tree: ast.AST,
    source_module: str,
    path: str,
) -> Tuple[List[str], Set[str]]:
    violations: List[str] = []
    edges: Set[str] = set()
    for node in ast.walk(tree):
        candidates: Sequence[str]
        if isinstance(node, ast.Import):
            candidates = tuple(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            candidates = _from_candidates(node)
        else:
            continue

        for candidate in candidates:
            found, target = _classify_core_candidate(
                source_module, candidate, path, node.lineno
            )
            violations.extend(found)
            if target is not None:
                edges.add(target)
    return violations, edges


def _adapter_core_targets(node: ast.AST) -> Tuple[str, ...]:
    if isinstance(node, ast.Import):
        targets = []
        for alias in node.names:
            target = _absolute_core_target(alias.name)
            if target is not None:
                targets.append(target)
        return tuple(targets)

    if not isinstance(node, ast.ImportFrom):
        return ()

    module = node.module or ""
    if node.level:
        if module == "core":
            return tuple(alias.name.split(".", 1)[0] for alias in node.names)
        if module.startswith("core."):
            return (module[len("core.") :].split(".", 1)[0],)
        if not module and any(alias.name == "core" for alias in node.names):
            return ("core",)
        return ()

    targets = []
    for candidate in _from_candidates(node):
        target = _absolute_core_target(candidate)
        if target is not None:
            targets.append(target)
    return tuple(targets)


def _parse(path: Path, display_path: str) -> Tuple[Optional[ast.AST], List[str]]:
    try:
        source = path.read_text(encoding="utf-8")
        return ast.parse(source, filename=display_path), []
    except (SyntaxError, UnicodeDecodeError) as error:
        line = error.lineno if isinstance(error, SyntaxError) and error.lineno else 1
        return None, [
            _diagnostic(
                display_path,
                line,
                "python-parse-error",
                "cannot parse Python source: "
                + (error.msg if isinstance(error, SyntaxError) else str(error)),
            )
        ]


def _canonical_cycle(cycle: Sequence[str]) -> Tuple[str, ...]:
    body = tuple(cycle[:-1])
    rotations = tuple(body[index:] + body[:index] for index in range(len(body)))
    selected = min(rotations)
    return selected + (selected[0],)


def _cycles(graph: Dict[str, Set[str]]) -> List[Tuple[str, ...]]:
    state: Dict[str, int] = {module: 0 for module in graph}
    stack: List[str] = []
    found: Set[Tuple[str, ...]] = set()

    def visit(module: str) -> None:
        state[module] = 1
        stack.append(module)
        for target in sorted(graph[module]):
            if target not in graph:
                continue
            if state[target] == 0:
                visit(target)
            elif state[target] == 1:
                start = stack.index(target)
                found.add(_canonical_cycle(tuple(stack[start:]) + (target,)))
        stack.pop()
        state[module] = 2

    for module in sorted(graph):
        if state[module] == 0:
            visit(module)
    return sorted(found)


def check_tree(
    core_root: Path,
    scripts_regression_root: Optional[Path] = None,
) -> list[str]:
    core_root = Path(core_root)
    regression_root = (
        Path(scripts_regression_root)
        if scripts_regression_root is not None
        else core_root.parent
    )
    if not core_root.is_dir():
        return [
            _diagnostic(
                "core",
                0,
                "missing-core-root",
                f"core directory does not exist: {core_root}",
            )
        ]

    violations: List[str] = []
    graph: Dict[str, Set[str]] = {}
    for path in sorted(core_root.rglob("*.py")):
        relative = path.relative_to(core_root)
        display_path = str(Path("core") / relative)
        module = _module_name(path, core_root)
        tree, parse_failures = _parse(path, display_path)
        violations.extend(parse_failures)
        graph.setdefault(module, set())
        if tree is None:
            continue
        import_failures, edges = _core_imports(tree, module, display_path)
        violations.extend(import_failures)
        graph[module].update(edges)

    for cycle in _cycles(graph):
        violations.append(
            _diagnostic(
                "core",
                0,
                "core-import-cycle",
                " -> ".join(cycle),
            )
        )

    for area in ("operations", "oracles"):
        adapter_root = regression_root / area
        if not adapter_root.is_dir():
            continue
        for path in sorted(adapter_root.rglob("*.py")):
            relative = path.relative_to(regression_root)
            display_path = str(relative)
            tree, parse_failures = _parse(path, display_path)
            violations.extend(parse_failures)
            if tree is None:
                continue
            for node in ast.walk(tree):
                for target in _adapter_core_targets(node):
                    if target not in PUBLIC_ADAPTER_CORE_MODULES:
                        violations.append(
                            _diagnostic(
                                display_path,
                                node.lineno,
                                "private-core-import",
                                "adapter may import only core contracts, digest, and ids; "
                                f"found '{target}'",
                            )
                        )

    return sorted(set(violations))


def main() -> int:
    if len(sys.argv) != 1:
        print("usage: verify_regression_core_layering.py", file=sys.stderr)
        return 2

    violations = check_tree(CORE_ROOT, REGRESSION_ROOT)
    if violations:
        print("Regression core layering verification failed:", file=sys.stderr)
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1

    print("Regression core layering verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
