#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_ROOTS = (
    Path("Modules/DesignSystem"),
    Path("Modules/Playback/Views"),
    Path("Modules/MediaLibrary"),
    Path("Apps/Enchron"),
)
CONTROL_PATTERN = re.compile(r"\b(?P<control>Button|Menu)\b\s*(?:\(|\{)")
TYPE_PATTERN = re.compile(
    r"\bstruct\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)[^\n{]*:\s*[^\n{]*\bView\b[^\n{]*\{"
)
DIRECT_HOVER_SHAPE_PATTERN = re.compile(r"\.enchronHoverContentShape\s*\(")
DIRECT_HOVER_EFFECT_PATTERN = re.compile(r"\.enchronHoverEffect\s*\(")
GLASS_HOVER_PATTERN = re.compile(
    r"\.enchronGlass(?:Control|Card|MenuItem|Pill)\s*\("
)
EXPANDED_FRAME_PATTERN = re.compile(
    r"\.frame\s*\([^)]*(?:targetSize|"
    r"min(?:Width|Height)\s*:\s*DesignTokens\.Interactive\.large|"
    r"(?:width|height)\s*:\s*DesignTokens\.Interactive\.large)"
    r"[^)]*\)",
    flags=re.DOTALL,
)
EXPANDED_PADDING_PATTERN = re.compile(
    r"\.padding\s*\([^)]*(?:DesignTokens\.Interactive\.large\s*-|"
    r"targetSize\s*-)"
    r"[^)]*\)",
    flags=re.DOTALL,
)
ANY_LAYOUT_AFTER_HOVER_PATTERN = re.compile(r"\.(?:frame|padding)\s*\(")
GENERIC_LABEL_PATTERN = re.compile(r"\blabel\s*\(\s*\)")


@dataclass(frozen=True)
class Finding:
    classification: str
    path: str
    line: int
    control: str
    reason: str


def mask_comments_and_strings(source: str) -> str:
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
            if current == "\n":
                in_string = False
            elif escaped:
                escaped = False
            elif current == "\\":
                escaped = True
            elif current == '"':
                in_string = False
            if current != "\n":
                characters[index] = " "
            index += 1
            continue

        if current == '"':
            characters[index] = " "
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


def matching_brace(masked: str, opening: int) -> int | None:
    depth = 0
    for index in range(opening, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def hover_carrier_names(sources: dict[Path, str]) -> set[str]:
    names: set[str] = set()
    for source in sources.values():
        masked = mask_comments_and_strings(source)
        for match in TYPE_PATTERN.finditer(masked):
            opening = masked.find("{", match.start())
            closing = matching_brace(masked, opening)
            if closing is None:
                continue
            body = masked[opening : closing + 1]
            owns_hover_shape = DIRECT_HOVER_SHAPE_PATTERN.search(body) is not None
            owns_hover_effect = DIRECT_HOVER_EFFECT_PATTERN.search(body) is not None
            owns_glass_hover = GLASS_HOVER_PATTERN.search(body) is not None
            if owns_hover_shape and (owns_hover_effect or owns_glass_hover):
                names.add(match.group("name"))
    return names


def control_regions(source: str) -> list[tuple[str, int, str]]:
    lines = source.splitlines()
    masked_lines = mask_comments_and_strings(source).splitlines()
    regions: list[tuple[str, int, str]] = []

    for start_index, masked_line in enumerate(masked_lines):
        for match in CONTROL_PATTERN.finditer(masked_line):
            indent = len(masked_line) - len(masked_line.lstrip())
            brace_depth = 0
            paren_depth = 0
            bracket_depth = 0
            saw_closure = False
            end_index = start_index

            for index in range(start_index, len(masked_lines)):
                line = masked_lines[index]
                fragment = line[match.start() :] if index == start_index else line
                if index > start_index and saw_closure:
                    stripped = line.strip()
                    current_indent = len(line) - len(line.lstrip())
                    neutral = brace_depth == paren_depth == bracket_depth == 0
                    continuation = (
                        not stripped
                        or stripped.startswith(".")
                        or (stripped.startswith("}") and current_indent >= indent)
                        or re.match(r"[A-Za-z_][A-Za-z0-9_]*\s*:\s*\{", stripped)
                        is not None
                        or current_indent > indent
                    )
                    if neutral and not continuation:
                        break

                brace_depth += fragment.count("{") - fragment.count("}")
                paren_depth += fragment.count("(") - fragment.count(")")
                bracket_depth += fragment.count("[") - fragment.count("]")
                saw_closure = saw_closure or "{" in fragment
                end_index = index

            regions.append(
                (
                    match.group("control"),
                    start_index + 1,
                    "\n".join(lines[start_index : end_index + 1]),
                )
            )
    return regions


def first_visual_hover_position(region: str, carrier_names: set[str]) -> int | None:
    positions: list[int] = []
    for pattern in (DIRECT_HOVER_SHAPE_PATTERN, GLASS_HOVER_PATTERN):
        positions.extend(match.start() for match in pattern.finditer(region))
    for name in carrier_names:
        match = re.search(rf"\b{re.escape(name)}\s*\(", region)
        if match:
            positions.append(match.start())
    return min(positions) if positions else None


def inset_hover_after(region: str, expansion_end: int) -> bool:
    tail = region[expansion_end:]
    for match in DIRECT_HOVER_SHAPE_PATTERN.finditer(tail):
        call_tail = tail[match.start() : match.start() + 700]
        if "insets:" in call_tail:
            return True
    return False


def audit_source(
    relative_path: Path,
    source: str,
    carrier_names: set[str],
) -> tuple[list[Finding], int]:
    findings: list[Finding] = []
    regions = control_regions(source)
    for control, line, region in regions:
        visual_position = first_visual_hover_position(region, carrier_names)
        if visual_position is None:
            generic_label = GENERIC_LABEL_PATTERN.search(region)
            generic_expansions = [
                match
                for pattern in (EXPANDED_FRAME_PATTERN, EXPANDED_PADDING_PATTERN)
                for match in pattern.finditer(region, generic_label.end() if generic_label else 0)
            ]
            if generic_label and generic_expansions:
                expansion = min(generic_expansions, key=lambda match: match.start())
                if not inset_hover_after(region, expansion.end()):
                    findings.append(
                        Finding(
                            classification="review",
                            path=relative_path.as_posix(),
                            line=line,
                            control=control,
                            reason=(
                                "generic label precedes an enlarged interaction target; "
                                "inspect its callers for smaller visual hover bounds"
                            ),
                        )
                    )
                continue

            effect = DIRECT_HOVER_EFFECT_PATTERN.search(region)
            layout = ANY_LAYOUT_AFTER_HOVER_PATTERN.search(
                region,
                effect.end() if effect else 0,
            ) if effect else None
            if effect and layout and not inset_hover_after(region, layout.end()):
                findings.append(
                    Finding(
                        classification="review",
                        path=relative_path.as_posix(),
                        line=line,
                        control=control,
                        reason=(
                            "hover effect precedes a larger layout, but the source does not "
                            "declare a visual hover content shape"
                        ),
                    )
                )
            continue

        expansions = [
            match
            for pattern in (EXPANDED_FRAME_PATTERN, EXPANDED_PADDING_PATTERN)
            for match in pattern.finditer(region, visual_position)
        ]
        if not expansions:
            later_layout = ANY_LAYOUT_AFTER_HOVER_PATTERN.search(region, visual_position)
            if later_layout and not inset_hover_after(region, later_layout.end()):
                findings.append(
                    Finding(
                        classification="review",
                        path=relative_path.as_posix(),
                        line=line,
                        control=control,
                        reason=(
                            "visual hover declaration precedes layout growth that the "
                            "high-confidence size rules cannot classify"
                        ),
                    )
                )
            continue

        expansion = min(expansions, key=lambda match: match.start())
        if not inset_hover_after(region, expansion.end()):
            findings.append(
                Finding(
                    classification="violation",
                    path=relative_path.as_posix(),
                    line=line,
                    control=control,
                    reason=(
                        "visual hover bounds are followed by an enlarged interaction target "
                        "without a post-expansion inset hover shape"
                    ),
                )
            )
    return findings, len(regions)


def production_sources(root: Path) -> dict[Path, str]:
    sources: dict[Path, str] = {}
    for relative_root in PRODUCTION_ROOTS:
        absolute_root = root / relative_root
        if not absolute_root.exists():
            continue
        for path in sorted(absolute_root.rglob("*.swift")):
            relative_path = path.relative_to(root)
            sources[relative_path] = path.read_text(encoding="utf-8")
    return sources


def self_test() -> None:
    fixtures = {
        "violation": """
struct VisualLabel: View {
    var body: some View {
        Circle().enchronHoverContentShape(Circle()).enchronHoverEffect()
    }
}
struct Host: View {
    var body: some View {
        Button { } label: {
            VisualLabel().frame(width: targetSize, height: targetSize).contentShape(Circle())
        }
        .contentShape(Circle())
    }
}
""",
        "fixed": """
struct VisualLabel: View {
    var body: some View {
        Circle().enchronHoverContentShape(Circle()).enchronHoverEffect()
    }
}
struct Host: View {
    var body: some View {
        Button { } label: {
            VisualLabel().frame(width: targetSize, height: targetSize).contentShape(Circle())
        }
        .contentShape(Circle())
        .enchronHoverContentShape(Circle(), insets: EdgeInsets())
    }
}
""",
        "same_bounds": """
struct Host: View {
    var body: some View {
        Button { } label: {
            Circle().frame(width: 44, height: 44)
                .enchronHoverContentShape(Circle()).enchronHoverEffect()
        }
    }
}
""",
    }
    expected = {"violation": 1, "fixed": 0, "same_bounds": 0}
    for name, source in fixtures.items():
        carriers = hover_carrier_names({Path(f"{name}.swift"): source})
        findings, _ = audit_source(Path(f"{name}.swift"), source, carriers)
        violations = sum(finding.classification == "violation" for finding in findings)
        if violations != expected[name]:
            raise RuntimeError(
                f"self-test {name} expected {expected[name]} violations, got {violations}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit production SwiftUI controls for hover regions enlarged with hit targets."
    )
    parser.add_argument("--root", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    self_test()
    sources = production_sources(root)
    carriers = hover_carrier_names(sources)
    findings: list[Finding] = []
    control_count = 0
    for relative_path, source in sources.items():
        source_findings, source_control_count = audit_source(
            relative_path,
            source,
            carriers,
        )
        findings.extend(source_findings)
        control_count += source_control_count

    violations = [finding for finding in findings if finding.classification == "violation"]
    reviews = [finding for finding in findings if finding.classification == "review"]
    if args.json:
        print(
            json.dumps(
                {
                    "swift_files": len(sources),
                    "controls": control_count,
                    "hover_carriers": sorted(carriers),
                    "violations": [asdict(finding) for finding in violations],
                    "review": [asdict(finding) for finding in reviews],
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        print(
            f"Scanned {len(sources)} production Swift files and {control_count} Button/Menu controls."
        )
        print(f"Confirmed violations: {len(violations)}")
        for finding in violations:
            print(f"  {finding.path}:{finding.line}: {finding.control}: {finding.reason}")
        print(f"Human-review candidates: {len(reviews)}")
        for finding in reviews:
            print(f"  {finding.path}:{finding.line}: {finding.control}: {finding.reason}")

    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
