#!/usr/bin/env python3

"""Literals that pin this repository to one machine, one network or one person.

Three scans run over different scopes, because the same literal is a defect in
one place and the subject of the work in another.

The RFC1918 scan covers the harness: `Scripts/verification`,
`Scripts/regression` and `Config`. A private address written into a runner
makes that runner drive one particular laboratory. The same address written
into an address-classification test is what the test exists to classify, so
this scan deliberately stops at the harness.

The wall-clock and absolute-path scans cover the regression contracts.

The identity scan covers every source and document tree in the repository. It
reports what would identify a real machine, a real network or a real person to
anyone reading the repository after it is published, in four classes: a
routable public IPv4 address, a Tailscale MagicDNS name, an Apple device
identifier, and an Emby account identity - the account name as a credential
value, and the server-issued or user-issued identifiers beside it.

Five shapes are legitimate and go unreported. An address in a reserved block -
private, loopback, link-local, carrier-grade NAT, multicast, or one of the
RFC 5737 documentation ranges - reaches nothing. An address one step outside a
reserved block is a boundary probe, and `RemoteAddressScope` needs a pair of
them per block to test where its ranges end. A dotted quad introduced by a
version word, or standing as a single path segment in a URL that carries a
scheme, is a version number: a four-part Emby server release is not a host. An
Apple device identifier whose serial half is padded out of a handful of
repeated digits is a placeholder, not a headset. An identifier built out of a
repeated cycle of hex, or out of a handful of characters, is a fixture value
rather than one a server or a device issued; this covers both the Emby 32-hex
identifiers and the CoreDevice UUIDs, whose hex a test types the same way.

Two of the classes are only a defect in context, because their bare shape is
too common to report on sight. A UUID is a CoreDevice identifier when a device
word labels it - the last thing named before it, or the first thing named
after it, within `CONTEXT_WINDOW` characters - and a session id is the same
shape labelled `session`. A 32-hex string is an Emby identifier on the same
test, against the Emby keys.

Scope is decided by walking the filesystem. The guard self-test harness copies
the worktree to a location that is not a repository, where `git` exits 128, so
a scope derived from `git ls-files` would silently cover nothing there. Git is
asked one question only - which of the walked files it ignores - and a git that
cannot answer means every file is scanned.
"""

from __future__ import annotations
import ipaddress
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PATTERN = re.compile(r"\b(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b")
WALL_CLOCK_PATTERN = re.compile(r"\b(?:controlsAutoHideSeconds|settleDelayMillis)\s*[:=]\s*\d+")
ABSOLUTE_PATH_PATTERN = re.compile(r'":\s*"/[^"]*"')
DEVICE_ID_PATTERN = re.compile(r"\bdevice[_-]?id\b.*[0-9a-fA-F-]{8,}", re.IGNORECASE)
PORT_PATTERN = re.compile(r":\s*\d{4,5}\b")

IPV4_LITERAL = re.compile(r"(?<![\w.-])(\d{1,3}(?:\.\d{1,3}){3})(?![\w.-])")
TAILNET_NAME = re.compile(r"\b[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.ts\.net\b")
APPLE_DEVICE_ID = re.compile(r"\b0000[0-9A-Fa-f]{4}-([0-9A-Fa-f]{16})\b")
VERSION_CONTEXT = re.compile(r"\b(?:version|release|revision|tag)\b[^0-9A-Za-z,;/|()\[\]<>-]{0,12}$", re.IGNORECASE)
URL_SCHEME = re.compile(r"\b[A-Za-z][A-Za-z0-9+.-]*://")
PLACEHOLDER_DIGIT_COUNT = 3

CONTEXT_WINDOW = 40
"""How far a context word reaches, and the band the account-name class leaves it.

Measured over the tree at commit c913e2b2, before the identity scrub, where
every credential occurrence of the account name was still present. Of the
occurrences a credential word introduces, the furthest stands 7 characters
from that word, in `Tests/EmbyPackageTests/EmbyDecodingTests.swift`, where the
name follows `.name)` across an equality operator and a bracket. Of the
occurrences no credential word introduces, the closest stands 44, in
`Tests/EnchronAppUI/AGENTS.md` and its `CLAUDE.md`, where a line opens on a
`/Users/` path and then names a second path running through the volume that
carries the same word as the account.

Forty sits between those two readings. What a different window would report is
not derivable from them: `is_introduced_by` rejects a context word that an
intervening word separates from the literal, so widening the window admits a
candidate only where no such word stands between. Any claim about the window's
margin has to be measured by sweeping the value, not read off the two distances
above.
"""
INTERVENING_WORD = re.compile(r"[A-Za-z一-鿿]{3,}")
CORE_DEVICE_UUID = re.compile(
    r"(?<![0-9A-Za-z-])([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})(?![0-9A-Za-z-])"
)
CORE_DEVICE_CONTEXT = re.compile(
    r"(?:Core[\s_-]?Device(?:[\s_-]?Identifier)?"
    r"|Vision\s*Pro|devicectl|--device|device[\s_-]?id(?:entifier)?|头显)",
    re.IGNORECASE,
)
"""The words that turn a UUID on a line into a CoreDevice identifier.

Two spellings were missing and both are the ones this repository writes. The
separator was fixed - `CoreDevice` and `Core Device` and nothing else - so
`core_device`, `CORE_DEVICE` and the `ENCHRON_CORE_DEVICE` variable named none
of them, and the pinned constant the scrub removed read `CORE_DEVICE = "<uuid>"`.
The suffix was fixed too: `coreDeviceIdentifier` matched on its first half, and
`is_introduced_by` then read the rest of the same word, `Identifier`, as
something named in between. A context word has to swallow its own suffix or
the adjacency test rejects it for standing next to itself.
"""

EMBY_IDENTIFIER = re.compile(r"(?<![0-9A-Za-z])([0-9a-fA-F]{32})(?![0-9A-Za-z])")
EMBY_IDENTIFIER_CONTEXT = re.compile(
    r"(?:(?:server|user)[_-]?id(?:entifier|entity)?"
    r"|AccessToken|X-Emby-Token|\bId\b)",
    re.IGNORECASE,
)
"""The words that turn a 32-hex string on a line into an Emby identifier.

The suffix was fixed here the way it was fixed for `CORE_DEVICE_CONTEXT`, and
for the same reason. `ServerId` and `UserId` matched the head of
`serverIdentifier` and `userIdentity`, and `is_introduced_by` then read the
rest of the same word - `entifier`, `entity` - as something named in between,
so the word rejected itself for standing next to itself. This repository
already spells these keys out in full: `serverIdentityDigest` in
`Scripts/verification/reachability_matrix.py`, `server_identity_digest` on the
signature that carries it.
"""
ACCOUNT_NAME = "Corti" + "sol"
"""The Emby account name, assembled so this file does not carry the literal.

A denylist entry written out in full makes the guard report itself on every
run, and the file that names the thing to look for is the one place an
exemption would be indistinguishable from the leak.
"""
BARE_ACCOUNT_NAME = re.compile(r"\b(" + re.escape(ACCOUNT_NAME) + r")\b")
"""The account name at a word boundary, in whatever punctuation surrounds it.

Requiring a quote around it was a rule shaped to the leak that had already
been cleaned up. The name in backticks, in a shell word, in prose or bare in a
path is the same name, and the quoting says nothing about whether it is being
used as a login. What separates a login from the volume and share of the same
name is the credential-word window, together with the positions
`stands_in_a_credential_position` reads: of the occurrences of the name across
the scanned tree, the guard reports the ones a credential word introduces or a
credential position holds, and passes the rest.
"""
ACCOUNT_NAME_CONTEXT = re.compile(
    r"(?:user|name|account|login|\bPw\b|password|credential)", re.IGNORECASE
)
USERINFO_TERMINATORS = ("@", ":")
CREDENTIAL_FLAG = re.compile(r"(?:^|[\s'\"(=])--?u(?:ser)?[\s=]+$")
"""The command-line flag that labels the name it is given as a login.

`curl` documents the flag as `-u, --user <user:password>`. In its short form
the whole label is two characters, and `ACCOUNT_NAME_CONTEXT` has no word to
find on such a line. The long form carries `user` and that pattern already
reads it; both are written here so one rule covers the flag rather than two
unrelated ones covering one spelling each.
"""

EXCLUDED_SEGMENTS = frozenset({
    "Vendor", ".build", ".scratch", ".git", "DerivedData", "SourcePackages",
    "checkouts", "node_modules",
})
EXCLUDED_ROOTS = (".claude/state", ".claude/worktrees")
BINARY_SUFFIXES = frozenset({
    ".a", ".aac", ".ac3", ".bin", ".bz2", ".car", ".dds", ".dmg", ".dylib",
    ".ear", ".exr", ".gif", ".gz", ".heic", ".hdr", ".icns", ".ico", ".idx",
    ".ipa", ".jpeg", ".jpg", ".ktx", ".m2ts", ".m4a", ".m4v", ".mka", ".mkv",
    ".mov", ".mp3", ".mp4", ".nib", ".o", ".otf", ".pack", ".pdf", ".png",
    ".pyc", ".reality", ".so", ".sqlite", ".tar", ".tiff", ".ttf", ".usdz",
    ".wav", ".webp", ".woff", ".woff2", ".xz", ".zip",
})
BINARY_SNIFF_BYTES = 4096
RESERVED_BLOCKS = (
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.0.2.0/24",
    "192.168.0.0/16",
    "198.51.100.0/24",
    "203.0.113.0/24",
    "224.0.0.0/4",
    "240.0.0.0/4",
)

def boundary_addresses() -> frozenset[str]:
    """The address one step outside each reserved block, on either side.

    A classification test proves where a range ends by naming the last address
    inside it and the first address outside it. The outside one is routable by
    definition, and is a constant of the range rather than a host.
    """
    edges: set[str] = set()
    for block in RESERVED_BLOCKS:
        network = ipaddress.IPv4Network(block)
        first = int(network.network_address)
        last = int(network.broadcast_address)
        if first > 0:
            edges.add(str(ipaddress.IPv4Address(first - 1)))
        if last < 2 ** 32 - 1:
            edges.add(str(ipaddress.IPv4Address(last + 1)))
    return frozenset(edges)

BOUNDARY_ADDRESSES = boundary_addresses()

def scan_roots() -> tuple[Path, ...]:
    return (
        REPOSITORY_ROOT / "Scripts/verification",
        REPOSITORY_ROOT / "Scripts/regression",
        REPOSITORY_ROOT / "Config",
    )

def r5_scan_roots() -> tuple[Path, ...]:
    return (
        REPOSITORY_ROOT / "Regression/operations",
        REPOSITORY_ROOT / "Regression/preparations",
        REPOSITORY_ROOT / "Config/regression/catalog-v2.json",
    )

def ignored_paths(paths: Sequence[Path]) -> frozenset[Path]:
    """Which of these files git ignores, asked once for all of them.

    The exemption this replaces was keyed on the name `*.local.json`, so a
    tracked file carrying that name was skipped along with the untracked one
    the pattern was written for. `git check-ignore` consults the index, so a
    tracked path is never reported ignored however the patterns read.

    A git that cannot answer means scan. The self-test harness copies the
    worktree out of the repository, where git exits 128; reading that as
    "ignored" would skip every file, and the guard would report green on a
    repository full of the thing it looks for.
    """
    if not paths:
        return frozenset()
    try:
        completed = subprocess.run(
            ["git", "-C", str(REPOSITORY_ROOT), "check-ignore", "--stdin", "-z"],
            input="\0".join(str(path) for path in paths),
            capture_output=True, text=True, check=False,
        )
    except (OSError, ValueError):
        return frozenset()
    if completed.returncode not in (0, 1):
        return frozenset()
    return frozenset(Path(name) for name in completed.stdout.split("\0") if name)

def reads_as_binary(path: Path) -> bool:
    """Whether the file is binary whatever its name says.

    `BINARY_SUFFIXES` names the formats worth skipping without opening. A NUL
    byte in the first block catches the rest, including the extensionless and
    oddly named result-bundle payloads no suffix list would have predicted.
    """
    try:
        with path.open("rb") as handle:
            return b"\0" in handle.read(BINARY_SNIFF_BYTES)
    except OSError:
        return True

def identity_scan_paths() -> list[Path]:
    """Every source and document file git would carry, found by walking.

    `EXCLUDED_ROOTS` names the two trees under `.claude` that are not this
    checkout's own material: the agent session state, and the sibling
    worktrees whose contents belong to another checkout of this repository.

    What to open is decided by a denylist, not by an allowlist of extensions.
    An allowlist skips whatever extension nobody thought of, which is how
    `.toml`, `.mdc`, `.usda`, `.tsv`, `.resolved`, `.log`, `.xcworkspacedata`
    and every extensionless file went unopened. A denylist fails toward
    scanning, and the binary sniff keeps the noise out.
    """
    candidates: list[Path] = []
    for directory, subdirectories, filenames in os.walk(REPOSITORY_ROOT):
        here = Path(directory)
        subdirectories[:] = sorted(
            name for name in subdirectories
            if name not in EXCLUDED_SEGMENTS
            and (here / name).relative_to(REPOSITORY_ROOT).as_posix() not in EXCLUDED_ROOTS
        )
        for filename in sorted(filenames):
            path = here / filename
            if path.suffix.lower() in BINARY_SUFFIXES:
                continue
            candidates.append(path)
    ignored = ignored_paths(candidates)
    return [
        path for path in candidates
        if path not in ignored and not reads_as_binary(path)
    ]

def reads_as_a_version(line: str, start: int, end: int) -> bool:
    """Whether a dotted quad on this line is a version number, not an address.

    Two shapes carry that meaning: a version word standing as a whole word
    in front of it and bound to it, by quoting, a colon, an equals sign, a
    space or a copula; and a single path segment in a URL, which is how a
    repository tag is cited. A dash, a comma or a slash in between is not a
    binding - it sets two things side by side, so `Release  - <quad>` reads as
    a release and then an address, and the address is reported.
    """
    if VERSION_CONTEXT.search(line[:start]):
        return True
    return sits_in_a_url_path(line, start, end)

def sits_in_a_url_path(line: str, start: int, end: int) -> bool:
    """Whether the quad stands as one path segment of a URL that carries a scheme.

    A host in a URL sits in the authority, directly behind the scheme's two
    slashes, not behind a third. A slash with no scheme anywhere in front of
    it belongs to a filesystem path or to prose, and a quad there is an
    address.
    """
    if line[start - 1: start] != "/" or line[end: end + 1] != "/":
        return False
    if line[max(start - 2, 0): max(start - 1, 0)] == "/":
        return False
    return URL_SCHEME.search(line[:start]) is not None

def reads_as_a_placeholder(serial: str) -> bool:
    """Whether an Apple device identifier's serial half was typed, not read off a headset."""
    return len(set(serial.lower())) <= PLACEHOLDER_DIGIT_COUNT

def reads_as_a_fixture_identifier(value: str) -> bool:
    """Whether a 32-hex identifier was typed into a fixture, not issued by a server.

    A server issues random hex. A fixture value is visibly patterned: it
    repeats a shorter cycle, or it is built out of a handful of characters.
    """
    lowered = value.lower()
    if len(set(lowered)) <= PLACEHOLDER_DIGIT_COUNT:
        return True
    for period in range(1, len(lowered) // 2 + 1):
        if len(lowered) % period:
            continue
        if lowered == lowered[:period] * (len(lowered) // period):
            return True
    return False

def stands_inside_an_authority(line: str, start: int) -> bool:
    """Whether the literal at `start` is still inside the authority a scheme opened.

    A scheme anywhere on the line proves nothing: a path, a prose sentence and
    a URL can share one line, and the name may sit in any of them. The
    authority ends at the first slash after the scheme's own two, so a scheme
    introduces the literal only when it opens before it and no slash stands
    between them.
    """
    for match in URL_SCHEME.finditer(line):
        if match.end() > start:
            break
        if "/" not in line[match.end():start]:
            return True
    return False

def stands_in_a_credential_position(line: str, start: int, end: int) -> bool:
    """Whether the name stands where a login goes, on a line that names no credential word.

    `ACCOUNT_NAME_CONTEXT` reads words, and two credential shapes carry no
    word to read. In a URL the login occupies the userinfo position, ahead of
    the at-sign that ends it or of the colon that separates it from a
    password, and the only word on such a line may be the scheme. The two SMB
    tools write that authority with no scheme in front of it - `mount_smbfs`
    and `smbutil` both take `//[domain;][user[:password]@]server` - so a name
    standing directly behind an authority's two slashes counts as well. On a
    command line the flag is the label, and `CREDENTIAL_FLAG` reads it.

    No occurrence of either shape exists in the scanned tree. This is the
    class the account-name rule could not see, not one it missed.
    """
    if CREDENTIAL_FLAG.search(line[:start]):
        return True
    if line[end: end + 1] not in USERINFO_TERMINATORS:
        return False
    if line[max(start - 2, 0): start] == "//":
        return True
    return stands_inside_an_authority(line, start)

def is_introduced_by(context: re.Pattern[str], line: str, start: int, end: int) -> bool:
    """Whether a word matching `context` labels the literal between `start` and `end`.

    Proximity alone is not enough. `Physical Vision Pro REDACTED, session
    <uuid>` puts a device word twenty-two characters in front of a session
    identifier, so the test is adjacency in naming rather than in characters:
    the context word is the last thing named before the literal, or the first
    thing named after it, with nothing but punctuation and short connectives
    in between.
    """
    before = line[max(start - CONTEXT_WINDOW, 0): start]
    leading = list(context.finditer(before))
    if leading and INTERVENING_WORD.search(before[leading[-1].end():]) is None:
        return True
    after = line[end: end + CONTEXT_WINDOW]
    trailing = context.search(after)
    return trailing is not None and INTERVENING_WORD.search(after[:trailing.start()]) is None

def identity_failures() -> list[str]:
    found: list[str] = []
    for path in identity_scan_paths():
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
        for index, line in enumerate(text.splitlines(), start=1):
            for match in IPV4_LITERAL.finditer(line):
                literal = match.group(1)
                try:
                    address = ipaddress.IPv4Address(literal)
                except ValueError:
                    continue
                if not address.is_global or address.is_multicast:
                    continue
                if literal in BOUNDARY_ADDRESSES:
                    continue
                if reads_as_a_version(line, match.start(1), match.end(1)):
                    continue
                found.append(f"{relative}:{index}: contains a routable public IPv4 address")
            if TAILNET_NAME.search(line):
                found.append(f"{relative}:{index}: contains a Tailscale MagicDNS name")
            for match in APPLE_DEVICE_ID.finditer(line):
                if reads_as_a_placeholder(match.group(1)):
                    continue
                found.append(f"{relative}:{index}: contains an Apple device identifier")
            for match in CORE_DEVICE_UUID.finditer(line):
                if not is_introduced_by(CORE_DEVICE_CONTEXT, line, match.start(1), match.end(1)):
                    continue
                if reads_as_a_fixture_identifier(match.group(1).replace("-", "")):
                    continue
                found.append(f"{relative}:{index}: contains a CoreDevice identifier")
            for match in EMBY_IDENTIFIER.finditer(line):
                if not is_introduced_by(EMBY_IDENTIFIER_CONTEXT, line, match.start(1), match.end(1)):
                    continue
                if reads_as_a_fixture_identifier(match.group(1)):
                    continue
                found.append(f"{relative}:{index}: contains an Emby server or user identifier")
            for match in BARE_ACCOUNT_NAME.finditer(line):
                start, stop = match.start(1), match.end(1)
                window = line[max(start - CONTEXT_WINDOW, 0): stop + CONTEXT_WINDOW]
                if not ACCOUNT_NAME_CONTEXT.search(window) and not stands_in_a_credential_position(line, start, stop):
                    continue
                found.append(f"{relative}:{index}: contains the Emby account name")
    return found

def failures() -> list[str]:
    found: list[str] = []
    for root in scan_roots():
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".json", ".md", ".txt", ".sh", ".zsh"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for index, line in enumerate(text.splitlines(), start=1):
                if PATTERN.search(line):
                    relative = path.relative_to(REPOSITORY_ROOT).as_posix()
                    found.append(f"{relative}:{index}: contains literal RFC1918 address")
    for root in r5_scan_roots():
        if root.is_file():
            paths = [root]
        elif root.is_dir():
            paths = sorted(root.rglob("*"))
        else:
            continue
        for path in paths:
            if not path.is_file():
                continue
            if path.suffix not in {".py", ".json", ".md"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            relative = path.relative_to(REPOSITORY_ROOT).as_posix()
            for index, line in enumerate(text.splitlines(), start=1):
                if WALL_CLOCK_PATTERN.search(line):
                    if "estimatedCostMillis" in line:
                        continue
                    found.append(f"{relative}:{index}: contains literal wall-clock timeout")
                if ABSOLUTE_PATH_PATTERN.search(line):
                    if "repo://" in line or "workspace://" in line or "result://" in line:
                        continue
                    stripped = line.strip()
                    if '"/' in line and not stripped.startswith('"'):
                        if re.search(r'"/(?:Users|var|tmp|private|Volumes)/', line):
                            found.append(f"{relative}:{index}: contains absolute path literal")
    found.extend(identity_failures())
    return sorted(found)

def main() -> int:
    found = failures()
    for line in found:
        print(line)
    if found:
        print(f"{len(found)} tracked-identity violations")
        return 1
    count = 0
    for root in scan_roots():
        if root.is_dir():
            count += sum(1 for _ in root.rglob("*") if _.is_file())
    print(f"no literal RFC1918 in {count} harness files")
    print(f"no tracked identity in {len(identity_scan_paths())} source and document files")
    return 0

if __name__ == "__main__":
    sys.exit(main())
