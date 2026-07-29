#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = Path("Config/design_source_architecture_baseline.json")

PRODUCTION_IMPORTS = {
    "DesignSystem",
    "MediaLibrary",
    "PlaybackFeature",
    "PlaybackPresentation",
}
PREVIEW_SHELL_FILES = {
    Path("Apps/DesignPreview/ContentView.swift"),
    Path("Apps/DesignPreview/DesignPreviewApp.swift"),
    Path("Apps/DesignPreview/TokenPreviews.swift"),
}
PARALLEL_STYLE_PROTOCOLS = (
    "ButtonStyle",
    "PrimitiveButtonStyle",
    "ToggleStyle",
    "ViewModifier",
    "Shape",
    "InsettableShape",
)
RAW_CONTROL_PATTERN = re.compile(
    r"\b(?P<control>Button|Menu|Toggle|Slider|TextField)\s*(?:\{|\()",
    flags=re.MULTILINE,
)
PARALLEL_STYLE_PATTERN = re.compile(
    rf"\b(?:struct|class|enum)\s+[A-Za-z_][A-Za-z0-9_]*[^:\n]*:\s*"
    rf"[^{{]*?\b(?:{'|'.join(PARALLEL_STYLE_PROTOCOLS)})\b",
    flags=re.MULTILINE,
)
EXTENSION_PATTERN = re.compile(
    r"^\s*extension\s+[A-Za-z_][A-Za-z0-9_.<>]*",
    flags=re.MULTILINE,
)
IMPORT_PATTERN = re.compile(r"^\s*import\s+(?P<module>[A-Za-z_][A-Za-z0-9_]*)")
VIEW_DECLARATION_PATTERN = re.compile(
    r"\b(?:struct|class)\s+[A-Za-z_][A-Za-z0-9_]*[^:\n]*:\s*[^{]*?\bView\b",
    flags=re.MULTILINE,
)
TOKEN_STRUCTURE_PATTERNS = (
    re.compile(
        rf"\b(?:struct|class|enum)\s+[A-Za-z_][A-Za-z0-9_]*[^:\n]*:\s*"
        rf"[^{{\n]*\b(?:{'|'.join(PARALLEL_STYLE_PROTOCOLS)}|View)\b"
    ),
    re.compile(r"@ViewBuilder\b"),
    re.compile(r"->\s*some\s+View\b"),
    re.compile(
        r"\b(?:Button|Menu|Toggle|Slider|TextField|VStack|HStack|ZStack|"
        r"Image|Text|RoundedRectangle|Circle|Capsule)\s*\("
    ),
)
VISUAL_LITERAL_PATTERNS = (
    re.compile(
        r"\.(?:frame|padding|offset|opacity|scaleEffect|cornerRadius|blur|shadow)"
        r"\s*\([^)]*(?<![A-Za-z_])\d+(?:\.\d+)?(?![A-Za-z_])"
    ),
    re.compile(
        r"\b(?:VStack|HStack|ZStack|LazyVGrid|LazyHGrid|Grid)\s*"
        r"\([^)]*\bspacing:\s*-?\d+(?:\.\d+)?"
    ),
    re.compile(
        r"\b(?:RoundedRectangle|UnevenRoundedRectangle)\s*"
        r"\([^)]*\bcornerRadius:\s*\d+(?:\.\d+)?"
    ),
    re.compile(r"\.font\s*\(\s*\.system\s*\([^)]*\bsize:\s*\d+(?:\.\d+)?"),
    re.compile(r"\.stroke(?:Border)?\s*\([^)]*\blineWidth:\s*\d+(?:\.\d+)?"),
)


@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int
    signature: str
    message: str

    @property
    def baseline_key(self) -> tuple[str, str, str]:
        return (self.rule, self.path, self.signature)


def normalized_signature(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip())


def code_line(line: str) -> str:
    return "" if line.lstrip().startswith("//") else line


def mask_swift_comments(source: str) -> str:
    characters = list(source)
    index = 0
    block_depth = 0
    in_string = False
    escaped = False
    while index < len(characters):
        current = characters[index]
        following = characters[index + 1] if index + 1 < len(characters) else ""

        if block_depth:
            if current == "/" and following == "*":
                characters[index] = characters[index + 1] = " "
                block_depth += 1
                index += 2
                continue
            if current == "*" and following == "/":
                characters[index] = characters[index + 1] = " "
                block_depth -= 1
                index += 2
                continue
            if current != "\n":
                characters[index] = " "
            index += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif current == "\\":
                escaped = True
            elif current == '"':
                in_string = False
            index += 1
            continue

        if current == '"':
            in_string = True
            index += 1
            continue
        if current == "/" and following == "/":
            while index < len(characters) and characters[index] != "\n":
                characters[index] = " "
                index += 1
            continue
        if current == "/" and following == "*":
            characters[index] = characters[index + 1] = " "
            block_depth = 1
            index += 2
            continue
        index += 1
    return "".join(characters)


def finding_line(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def signature_at(lines: list[str], line_number: int) -> str:
    return normalized_signature(lines[line_number - 1])


def source_lines(path: Path) -> list[tuple[int, str]]:
    return list(enumerate(path.read_text(encoding="utf-8").splitlines(), start=1))


def relative_swift_files(root: Path, directory: str) -> list[Path]:
    base = root / directory
    if not base.exists():
        return []
    return sorted(path.relative_to(root) for path in base.rglob("*.swift"))


def find_token_layer_violations(root: Path) -> list[Finding]:
    relative_path = Path("Modules/DesignSystem/DesignTokens.swift")
    path = root / relative_path
    if not path.exists():
        return []

    source = path.read_text(encoding="utf-8")
    masked_source = mask_swift_comments(source)
    lines = source.splitlines()
    findings = []
    matched_offsets = set()
    for pattern in TOKEN_STRUCTURE_PATTERNS:
        for match in pattern.finditer(masked_source):
            line_number = finding_line(masked_source, match.start())
            key = (line_number, signature_at(lines, line_number))
            if key in matched_offsets:
                continue
            matched_offsets.add(key)
            findings.append(
                Finding(
                    rule="token-layer-structure",
                    path=relative_path.as_posix(),
                    line=line_number,
                    signature=key[1],
                    message=(
                        "DesignTokens may contain visual values, not View structure, "
                        "component factories, or style implementations"
                    ),
                )
            )
    return findings


def preview_exhibition_file(relative_path: Path) -> bool:
    return (
        relative_path.parent == Path("Apps/DesignPreview")
        and relative_path not in PREVIEW_SHELL_FILES
    )


def find_preview_violations(
    root: Path,
    preview_sources: list[Path] | None = None,
) -> list[Finding]:
    findings = []
    sources = preview_sources
    if sources is None:
        sources = relative_swift_files(root, "Apps/DesignPreview")
    for relative_path in sources:
        path = root / relative_path
        lines = source_lines(path)
        source = "\n".join(line for _, line in lines)
        masked_source = mask_swift_comments(source)
        source_text_lines = source.splitlines()

        view_declaration = VIEW_DECLARATION_PATTERN.search(masked_source)
        if view_declaration and relative_path not in PREVIEW_SHELL_FILES:
            imports = {
                match.group("module")
                for _, line in lines
                if (match := IMPORT_PATTERN.match(line))
            }
            if not imports.intersection(PRODUCTION_IMPORTS):
                declaration_line = finding_line(masked_source, view_declaration.start())
                findings.append(
                    Finding(
                        rule="preview-production-import",
                        path=relative_path.as_posix(),
                        line=declaration_line,
                        signature="missing-production-module-import",
                        message=(
                            "DesignPreview view files must consume at least one production "
                            "module instead of forming a SwiftUI-only implementation"
                        ),
                    )
                )

        for match in PARALLEL_STYLE_PATTERN.finditer(masked_source):
            line_number = finding_line(masked_source, match.start())
            findings.append(
                Finding(
                    rule="preview-parallel-style",
                    path=relative_path.as_posix(),
                    line=line_number,
                    signature=signature_at(source_text_lines, line_number),
                    message=(
                        "DesignPreview must use a production style or component; "
                        "custom style and Shape implementations belong in DesignSystem"
                    ),
                )
            )

        if preview_exhibition_file(relative_path):
            for match in EXTENSION_PATTERN.finditer(masked_source):
                line_number = finding_line(masked_source, match.start())
                findings.append(
                    Finding(
                        rule="preview-production-extension",
                        path=relative_path.as_posix(),
                        line=line_number,
                        signature=signature_at(source_text_lines, line_number),
                        message=(
                            "component variants and convenience factories must be "
                            "declared with their production component, not in DesignPreview"
                        ),
                    )
                )

            for match in RAW_CONTROL_PATTERN.finditer(masked_source):
                line_number = finding_line(masked_source, match.start())
                findings.append(
                    Finding(
                        rule="preview-raw-control",
                        path=relative_path.as_posix(),
                        line=line_number,
                        signature=signature_at(source_text_lines, line_number),
                        message=(
                            f"raw {match.group('control')} construction in "
                            "DesignPreview bypasses a production component"
                        ),
                    )
                )

            visual_offsets = set()
            for pattern in VISUAL_LITERAL_PATTERNS:
                for match in pattern.finditer(masked_source):
                    line_number = finding_line(masked_source, match.start())
                    key = (line_number, signature_at(source_text_lines, line_number))
                    if key in visual_offsets:
                        continue
                    visual_offsets.add(key)
                    findings.append(
                        Finding(
                            rule="preview-hardcoded-visual",
                            path=relative_path.as_posix(),
                            line=line_number,
                            signature=key[1],
                            message=(
                                "visual numeric literals in DesignPreview must come from "
                                "DesignTokens or a production component"
                            ),
                        )
                    )
    return findings


def collect_findings(
    root: Path,
    preview_sources: list[Path] | None = None,
) -> list[Finding]:
    return find_token_layer_violations(root) + find_preview_violations(root, preview_sources)


def xcode_preview_sources(root: Path) -> list[Path]:
    try:
        input_count = int(os.environ["SCRIPT_INPUT_FILE_COUNT"])
    except (KeyError, ValueError) as error:
        raise ValueError(
            "SCRIPT_INPUT_FILE_COUNT is missing; --xcode-inputs must run inside an "
            "Xcode Run Script phase"
        ) from error

    preview_root = (root / "Apps/DesignPreview").resolve()
    preview_sources = []
    for index in range(input_count):
        variable = f"SCRIPT_INPUT_FILE_{index}"
        raw_path = os.environ.get(variable)
        if raw_path is None:
            raise ValueError(f"{variable} is missing")
        path = Path(raw_path).resolve()
        try:
            relative_preview_path = path.relative_to(preview_root)
        except ValueError:
            continue
        if path.suffix != ".swift" or not relative_preview_path.parts:
            raise ValueError(
                f"{path} is too broad; DesignPreview Xcode inputs must name Swift files"
            )
        if not path.is_file():
            raise ValueError(f"declared DesignPreview Swift input does not exist: {path}")
        preview_sources.append(path.relative_to(root))

    if not preview_sources:
        raise ValueError("Xcode Run Script declared no DesignPreview Swift inputs")
    return sorted(set(preview_sources))


def find_xcode_build_input_violations(root: Path) -> list[Finding]:
    project_relative_path = Path("Enchron.xcodeproj/project.pbxproj")
    project_path = root / project_relative_path
    if not project_path.exists():
        return []

    project_source = project_path.read_text(encoding="utf-8")
    phase_pattern = re.compile(
        r"^[ \t]*[A-F0-9]{24} /\* Design Source Architecture \*/ = \{"
        r"(?P<body>.*?^[ \t]*\};)",
        flags=re.MULTILINE | re.DOTALL,
    )
    input_pattern = re.compile(
        r'"\$\(SRCROOT\)/(?P<path>Apps/DesignPreview/[^"]+\.swift)"'
    )
    expected_sources = {
        path.as_posix() for path in relative_swift_files(root, "Apps/DesignPreview")
    }
    findings = []
    phases = list(phase_pattern.finditer(project_source))
    if len(phases) != 3:
        findings.append(
            Finding(
                rule="xcode-build-inputs",
                path=project_relative_path.as_posix(),
                line=1,
                signature="design-source-architecture-phase-count",
                message=(
                    "Enchron, EnchronMacOS, and DesignPreview must each have one "
                    "Design Source Architecture build phase"
                ),
            )
        )

    for phase in phases:
        body = phase.group("body")
        declared_sources = {
            match.group("path") for match in input_pattern.finditer(body)
        }
        if declared_sources == expected_sources and "--xcode-inputs" in body:
            continue
        line_number = finding_line(project_source, phase.start())
        missing = sorted(expected_sources - declared_sources)
        stale = sorted(declared_sources - expected_sources)
        details = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if stale:
            details.append(f"stale {', '.join(stale)}")
        if "--xcode-inputs" not in body:
            details.append("shell script does not use --xcode-inputs")
        findings.append(
            Finding(
                rule="xcode-build-inputs",
                path=project_relative_path.as_posix(),
                line=line_number,
                signature=normalized_signature(project_source.splitlines()[line_number - 1]),
                message=(
                    "Xcode Design Source Architecture inputs must exactly match "
                    f"DesignPreview Swift sources: {'; '.join(details)}"
                ),
            )
        )
    return findings


def read_baseline(path: Path) -> dict[tuple[str, str, str], int]:
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    baseline = {}
    for entry in payload.get("allowances", []):
        key = (entry["rule"], entry["path"], entry["signature"])
        baseline[key] = entry["count"]
    return baseline


def baseline_payload(findings: list[Finding]) -> dict:
    counts: dict[tuple[str, str, str], int] = defaultdict(int)
    for finding in findings:
        counts[finding.baseline_key] += 1
    allowances = [
        {
            "rule": rule,
            "path": path,
            "signature": signature,
            "count": count,
        }
        for (rule, path, signature), count in sorted(counts.items())
    ]
    return {
        "version": 1,
        "purpose": (
            "Exact historical DesignPreview source-architecture violations. "
            "New occurrences are forbidden; remove entries when the underlying code is fixed."
        ),
        "allowances": allowances,
    }


def verify(findings: list[Finding], baseline: dict[tuple[str, str, str], int]) -> list[str]:
    grouped: dict[tuple[str, str, str], list[Finding]] = defaultdict(list)
    for finding in findings:
        grouped[finding.baseline_key].append(finding)

    diagnostics = []
    for key, occurrences in sorted(grouped.items()):
        allowed_count = baseline.get(key, 0)
        for finding in occurrences[allowed_count:]:
            diagnostics.append(
                f"{finding.path}:{finding.line}: error: "
                f"[{finding.rule}] {finding.message}"
            )

    for key, allowed_count in sorted(baseline.items()):
        current_count = len(grouped.get(key, []))
        if current_count < allowed_count:
            rule, path, _ = key
            diagnostics.append(
                f"{path}:1: error: [baseline-stale] {rule} allowance is "
                f"{allowed_count}, but only {current_count} occurrence(s) remain; "
                "shrink the baseline"
            )
    return diagnostics


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Enforce DesignTokens, production-component, and DesignPreview source layers."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_REPOSITORY_ROOT,
        help="repository root to inspect",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="baseline path, relative to --root unless absolute",
    )
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="replace the baseline with the exact findings in the inspected tree",
    )
    parser.add_argument(
        "--xcode-inputs",
        action="store_true",
        help=(
            "inspect only DesignPreview Swift files declared by Xcode "
            "SCRIPT_INPUT_FILE_* variables"
        ),
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = arguments.root.resolve()
    baseline_path = arguments.baseline
    if not baseline_path.is_absolute():
        baseline_path = root / baseline_path

    try:
        preview_sources = xcode_preview_sources(root) if arguments.xcode_inputs else None
    except ValueError as error:
        print(f"{root}:1: error: [xcode-input-scope] {error}", file=sys.stderr)
        return 1

    findings = collect_findings(root, preview_sources)
    if preview_sources is None:
        findings += find_xcode_build_input_violations(root)
    if arguments.write_baseline:
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps(baseline_payload(findings), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {len(findings)} exact allowance occurrence(s) to {baseline_path}")
        return 0

    diagnostics = verify(findings, read_baseline(baseline_path))
    if diagnostics:
        print("\n".join(diagnostics), file=sys.stderr)
        return 1

    print(
        "Design source architecture passed: "
        "DesignTokens values, production components, and DesignPreview composition are separated"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
