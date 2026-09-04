#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys


DEFAULT_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = Path("Config/design_source_architecture_baseline.json")
PRODUCTION_INPUT_LIST = Path("Config/design_source_architecture_inputs.xcfilelist")
PRODUCTION_SOURCE_DIRECTORIES = ("Apps/Enchron", "Modules")

PARALLEL_STYLE_PROTOCOLS = (
    "ButtonStyle",
    "PrimitiveButtonStyle",
    "ToggleStyle",
    "ViewModifier",
    "Shape",
    "InsettableShape",
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
NUMERIC_LITERAL = r"(?<![A-Za-z0-9_.])-?\d+(?:\.\d+)?(?![A-Za-z0-9_])"
NON_OPACITY_ENDPOINT_LITERAL = (
    r"(?<![A-Za-z0-9_.])"
    r"(?!(?:0(?:\.0+)?|1(?:\.0+)?)(?![\d.]))"
    r"-?\d+(?:\.\d+)?(?![A-Za-z0-9_])"
)
NON_TRIVIAL_LITERAL = NON_OPACITY_ENDPOINT_LITERAL
NON_IDENTITY_SCALE_LITERAL = (
    r"(?<![A-Za-z0-9_.])"
    r"(?!(?:1(?:\.0+)?)(?![\d.]))"
    r"-?\d+(?:\.\d+)?(?![A-Za-z0-9_])"
)
VISUAL_LITERAL_PATTERNS = (
    re.compile(
        r"\.(?:frame|padding|offset|cornerRadius|blur|shadow)"
        rf"\s*\([^)]*{NON_TRIVIAL_LITERAL}"
    ),
    re.compile(rf"\.opacity\s*\([^)]*{NON_OPACITY_ENDPOINT_LITERAL}"),
    re.compile(rf"\.scaleEffect\s*\([^)]*{NON_IDENTITY_SCALE_LITERAL}"),
    re.compile(
        r"\b(?:VStack|HStack|ZStack|LazyVGrid|LazyHGrid|Grid)\s*"
        rf"\([^)]*\bspacing:\s*{NON_TRIVIAL_LITERAL}"
    ),
    re.compile(
        r"\b(?:RoundedRectangle|UnevenRoundedRectangle)\s*"
        rf"\([^)]*\bcornerRadius:\s*{NON_TRIVIAL_LITERAL}"
    ),
    re.compile(
        rf"\.font\s*\(\s*\.system\s*\([^)]*\bsize:\s*{NON_TRIVIAL_LITERAL}"
    ),
    re.compile(
        rf"\.stroke(?:Border)?\s*\([^)]*\blineWidth:\s*{NON_TRIVIAL_LITERAL}"
    ),
)
PRODUCTION_GLASS_CAPSULE_PATTERN = re.compile(
    r"\.enchronGlassBackground\s*\(\s*in:\s*Capsule\s*\(\s*\)\s*\)",
    flags=re.MULTILINE,
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


def find_visual_literal_violations(
    relative_path: Path,
    source: str,
    *,
    rule: str,
    message: str,
) -> list[Finding]:
    masked_source = mask_swift_comments(source)
    source_text_lines = source.splitlines()
    findings = []
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
                    rule=rule,
                    path=relative_path.as_posix(),
                    line=line_number,
                    signature=key[1],
                    message=message,
                )
            )
    return findings


def find_production_violations(root: Path) -> list[Finding]:
    findings = []
    sources = (
        relative_swift_files(root, "Apps/Enchron")
        + relative_swift_files(root, "Modules")
    )
    design_system_root = Path("Modules/DesignSystem")
    for relative_path in sources:
        if relative_path.is_relative_to(design_system_root):
            continue
        path = root / relative_path
        source = path.read_text(encoding="utf-8")
        masked_source = mask_swift_comments(source)
        lines = source.splitlines()
        for match in PRODUCTION_GLASS_CAPSULE_PATTERN.finditer(masked_source):
            line_number = finding_line(masked_source, match.start())
            findings.append(
                Finding(
                    rule="production-parallel-glass-component",
                    path=relative_path.as_posix(),
                    line=line_number,
                    signature=signature_at(lines, line_number),
                    message=(
                        "production features must compose a DesignSystem glass component; "
                        "raw glass capsule construction belongs in Modules/DesignSystem"
                    ),
                )
            )
        findings += find_visual_literal_violations(
            relative_path,
            source,
            rule="production-hardcoded-visual",
            message=(
                "production visual numeric literals must come from DesignTokens "
                "or a DesignSystem component"
            ),
        )
    return findings


def collect_findings(root: Path) -> list[Finding]:
    return find_token_layer_violations(root) + find_production_violations(root)


def find_xcode_build_input_violations(root: Path) -> list[Finding]:
    project_relative_path = Path("Enchron.xcodeproj/project.pbxproj")
    project_path = root / project_relative_path
    if not project_path.exists():
        return []

    project_source = project_path.read_text(encoding="utf-8")
    production_inputs_path = root / PRODUCTION_INPUT_LIST
    expected_production_inputs = {
        f"$(SRCROOT)/{path.as_posix()}"
        for directory in PRODUCTION_SOURCE_DIRECTORIES
        for path in relative_swift_files(root, directory)
    }
    declared_production_inputs = (
        {
            line.strip()
            for line in production_inputs_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }
        if production_inputs_path.exists()
        else set()
    )
    phase_pattern = re.compile(
        r"^[ \t]*[A-F0-9]{24} /\* Design Source Architecture \*/ = \{"
        r"(?P<body>.*?^[ \t]*\};)",
        flags=re.MULTILINE | re.DOTALL,
    )
    findings = []
    if declared_production_inputs != expected_production_inputs:
        missing = sorted(expected_production_inputs - declared_production_inputs)
        stale = sorted(declared_production_inputs - expected_production_inputs)
        details = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if stale:
            details.append(f"stale {', '.join(stale)}")
        findings.append(
            Finding(
                rule="xcode-production-inputs",
                path=PRODUCTION_INPUT_LIST.as_posix(),
                line=1,
                signature="design-source-architecture-production-inputs",
                message=(
                    "Xcode's user script sandbox grants the Design Source "
                    "Architecture phase read access to its declared inputs and "
                    "nothing else, so a production Swift file missing from this "
                    "generated list is a build that dies on PermissionError "
                    f"rather than a stale manifest: {'; '.join(details)}"
                ),
            )
        )

    phases = list(phase_pattern.finditer(project_source))
    if not phases:
        findings.append(
            Finding(
                rule="xcode-build-inputs",
                path=project_relative_path.as_posix(),
                line=1,
                signature="design-source-architecture-phase-count",
                message=(
                    "the Enchron target must run one Design Source Architecture "
                    "build phase"
                ),
            )
        )

    for phase in phases:
        body = phase.group("body")
        has_production_input_list = (
            f'"$(SRCROOT)/{PRODUCTION_INPUT_LIST.as_posix()}"' in body
        )
        if "--xcode-inputs" in body and has_production_input_list:
            continue
        line_number = finding_line(project_source, phase.start())
        details = []
        if "--xcode-inputs" not in body:
            details.append("shell script does not use --xcode-inputs")
        if not has_production_input_list:
            details.append(
                f"missing production input list {PRODUCTION_INPUT_LIST.as_posix()}"
            )
        findings.append(
            Finding(
                rule="xcode-build-inputs",
                path=project_relative_path.as_posix(),
                line=line_number,
                signature=normalized_signature(project_source.splitlines()[line_number - 1]),
                message=(
                    "the Xcode Design Source Architecture phase must inspect "
                    "production sources under the user script sandbox: "
                    f"{'; '.join(details)}"
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
            "Exact historical design source-architecture violations. "
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
        description="Enforce the DesignTokens and production-component source layers."
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
        "--write-inputs",
        action="store_true",
        help=(
            "regenerate the production input list this script reads under Xcode's "
            "user script sandbox"
        ),
    )
    parser.add_argument(
        "--xcode-inputs",
        action="store_true",
        help=(
            "run under Xcode's user script sandbox, which cannot read the "
            "project file"
        ),
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = arguments.root.resolve()
    baseline_path = arguments.baseline
    if not baseline_path.is_absolute():
        baseline_path = root / baseline_path

    if arguments.write_inputs:
        inputs_path = root / PRODUCTION_INPUT_LIST
        entries = sorted(
            f"$(SRCROOT)/{path.as_posix()}"
            for directory in PRODUCTION_SOURCE_DIRECTORIES
            for path in relative_swift_files(root, directory)
        )
        inputs_path.parent.mkdir(parents=True, exist_ok=True)
        inputs_path.write_text("\n".join(entries) + "\n", encoding="utf-8")
        print(f"Wrote {len(entries)} production input(s) to {inputs_path}")
        return 0

    findings = collect_findings(root)
    if not arguments.xcode_inputs:
        findings += find_xcode_build_input_violations(root)
    if arguments.write_baseline:
        existing = read_baseline(baseline_path) if baseline_path.is_file() else set()
        arriving = sorted(
            f"{finding.rule} {finding.path} {finding.signature}"
            for finding in findings
            if f"{finding.rule} {finding.path} {finding.signature}" not in {
                f"{rule} {path} {signature}" for rule, path, signature, *_ in
                (entry if isinstance(entry, tuple) else (entry,) for entry in existing)
            }
        ) if existing else []
        if arriving:
            print(
                "refusing to widen the baseline; fix the code or argue the rule:\n  "
                + "\n  ".join(arriving),
                file=sys.stderr,
            )
            return 1
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
        "DesignTokens values and production components are separated"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
