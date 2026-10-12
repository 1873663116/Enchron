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
SHARED_HOVER_TARGET_PATTERN = re.compile(r"\.enchronHoverTarget\s*\(")
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
BACKGROUND_PATTERN = re.compile(r"\.(?:background|enchronGlassBackground|enchronButtonSurface)\s*(?=[({])")


def matching_delimiter(source: str, opening: int) -> int | None:
    pairs = {"(": ")", "{": "}", "[": "]"}
    stack: list[str] = []
    for index in range(opening, len(source)):
        character = source[index]
        if character in pairs:
            stack.append(pairs[character])
        elif character in pairs.values():
            if not stack or stack.pop() != character:
                return None
            if not stack:
                return index
    return None


def call_arguments(source: str, start: int) -> tuple[str, int] | None:
    opening = source.find("(", start)
    closing = matching_delimiter(source, opening) if opening >= 0 else None
    if closing is None:
        return None
    return source[opening + 1 : closing], closing + 1


def split_arguments(arguments: str) -> list[str]:
    result: list[str] = []
    start = 0
    depth = 0
    for index, character in enumerate(arguments):
        if character in "({[":
            depth += 1
        elif character in ")}]":
            depth -= 1
        elif character == "," and depth == 0:
            result.append(arguments[start:index].strip())
            start = index + 1
    result.append(arguments[start:].strip())
    return result


def hover_insets(arguments: str) -> str | None:
    for argument in split_arguments(arguments):
        match = re.match(r"insets\s*:\s*(.+)", argument, re.DOTALL)
        if match:
            return re.sub(r"\s+", "", match.group(1))
    return None


def delimiter_depths(source: str) -> list[int]:
    depths: list[int] = []
    depth = 0
    for character in source:
        depths.append(depth)
        if character in "({[":
            depth += 1
        elif character in ")}]":
            depth -= 1
    return depths


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
            if SHARED_HOVER_TARGET_PATTERN.search(body) or (owns_hover_shape and (owns_hover_effect or owns_glass_hover)):
                names.add(match.group("name"))
    return names


def control_regions(source: str, pattern: re.Pattern = CONTROL_PATTERN) -> list[tuple[str, int, str]]:
    lines = source.splitlines()
    masked_lines = mask_comments_and_strings(source).splitlines()
    regions: list[tuple[str, int, str]] = []

    for start_index, masked_line in enumerate(masked_lines):
        for match in pattern.finditer(masked_line):
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
    for pattern in (DIRECT_HOVER_SHAPE_PATTERN, GLASS_HOVER_PATTERN, SHARED_HOVER_TARGET_PATTERN):
        positions.extend(match.start() for match in pattern.finditer(region))
    for name in carrier_names:
        match = re.search(rf"\b{re.escape(name)}\s*\(", region)
        if match:
            positions.append(match.start())
    return min(positions) if positions else None


def inset_hover_after(region: str, expansion_end: int) -> bool:
    tail = mask_comments_and_strings(region)[expansion_end:]
    for match in DIRECT_HOVER_SHAPE_PATTERN.finditer(tail):
        call = call_arguments(tail, match.start())
        if call and hover_insets(call[0]) is not None:
            return True
    return False


def background_expansion_without_insets(region: str) -> bool:
    masked = mask_comments_and_strings(region)
    depths = delimiter_depths(masked)
    backgrounds = list(BACKGROUND_PATTERN.finditer(masked))
    for hover in DIRECT_HOVER_SHAPE_PATTERN.finditer(masked):
        previous = [
            background for background in backgrounds
            if background.start() < hover.start()
            and depths[background.start()] == depths[hover.start()]
        ]
        if not previous:
            continue
        background = previous[-1]
        opening = background.end()
        while masked[opening].isspace():
            opening += 1
        closing = matching_delimiter(masked, opening)
        if closing is None:
            continue
        expansions = [
            match for match in ANY_LAYOUT_AFTER_HOVER_PATTERN.finditer(masked, closing + 1, hover.start())
            if depths[match.start()] == depths[hover.start()]
        ]
        if not expansions:
            continue
        call = call_arguments(masked, hover.start())
        if not call or hover_insets(call[0]) is None:
            return True
        insets = hover_insets(call[0])
        for expansion in expansions:
            if masked[expansion.start():].startswith(".padding"):
                padding = call_arguments(masked, expansion.start())
                if padding and re.fullmatch(r"[A-Za-z_]\w*", padding[0].strip()):
                    if padding[0].strip() != insets:
                        return True
    return False


def style_regions(source: str) -> list[tuple[str, int, str]]:
    masked = mask_comments_and_strings(source)
    pattern = re.compile(r"\bstruct\s+\w+[^\n{]*:\s*[^\n{]*\bButtonStyle\b[^\n{]*\{")
    result = []
    for match in pattern.finditer(masked):
        opening = masked.find("{", match.start())
        closing = matching_brace(masked, opening)
        if closing is not None:
            result.append(("ButtonStyle", source.count("\n", 0, match.start()) + 1, source[opening:closing + 1]))
    return result


def shared_target_findings(relative_path: Path, source: str) -> list[Finding]:
    masked = mask_comments_and_strings(source)
    pattern = re.compile(r"\bfunc\s+enchronHoverTarget\b")
    findings = []
    for match in pattern.finditer(masked):
        opening = masked.find("{", match.start())
        closing = matching_brace(masked, opening)
        if closing is None:
            continue
        body = re.sub(r"\s+", "", masked[opening:closing + 1])
        required = ("EnchronHoverRegion(visual,insets:insets)", ".padding(insets)",
                    ".clipShape(hover)", ".contentShape(.interaction,interaction)",
                    ".contentShape(.hoverEffect,hover)", ".enchronHoverEffect(.highlight)")
        if any(term not in body for term in required):
            findings.append(Finding("violation", relative_path.as_posix(),
                                    source.count("\n", 0, match.start()) + 1, "HoverTarget",
                                    "shared hover target must clip the visible shape independently of the interaction shape"))
    container_pattern = re.compile(r"\b(?P<control>HStack|VStack|ZStack)\b\s*(?:\(|\{)")
    for control, line, region in control_regions(source, container_pattern):
        region = mask_comments_and_strings(region)
        opening = region.find("{")
        closing = matching_brace(region, opening)
        if closing is None:
            continue
        body = region[opening + 1:closing]
        body_depths = delimiter_depths(body)
        if sum(body_depths[match.start()] == 0 for match in CONTROL_PATTERN.finditer(body)) < 2:
            continue
        tail = region[closing + 1:]
        depths = delimiter_depths(tail)
        if any(depths[match.start()] == 0 for pattern in (DIRECT_HOVER_EFFECT_PATTERN, GLASS_HOVER_PATTERN)
               for match in pattern.finditer(tail)):
            findings.append(Finding("violation", relative_path.as_posix(), line, control,
                                    "container hover covers multiple buttons; attach hover to each visible button"))
    return findings


def audit_source(
    relative_path: Path,
    source: str,
    carrier_names: set[str],
) -> tuple[list[Finding], int]:
    findings = shared_target_findings(relative_path, source)
    regions = control_regions(source) + style_regions(source)
    for control, line, region in regions:
        region = mask_comments_and_strings(region)
        if control == "ButtonStyle":
            depths = delimiter_depths(region)
            hover = DIRECT_HOVER_SHAPE_PATTERN.search(region)
            if hover and any(depths[match.start()] == depths[hover.start()]
                             for match in ANY_LAYOUT_AFTER_HOVER_PATTERN.finditer(region, hover.end())):
                findings.append(Finding("violation", relative_path.as_posix(), line, control,
                                        "ButtonStyle expands a hover-bearing label; use the shared visual/interaction target"))
                continue
        if background_expansion_without_insets(region):
            findings.append(Finding(
                classification="violation",
                path=relative_path.as_posix(),
                line=line,
                control=control,
                reason="visual background is enlarged before hover without matching insets in that hover call",
            ))
            continue
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


def audit_sources(sources: dict[Path, str]) -> tuple[list[Finding], set[str], int]:
    carriers = hover_carrier_names(sources)
    findings: list[Finding] = []
    control_count = 0
    for relative_path, source in sources.items():
        source_findings, source_control_count = audit_source(relative_path, source, carriers)
        findings.extend(source_findings)
        control_count += source_control_count
    return findings, carriers, control_count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit production SwiftUI controls for hover regions enlarged with hit targets."
    )
    parser.add_argument("--root", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    sources = production_sources(root)
    findings, carriers, control_count = audit_sources(sources)

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
            f"Scanned {len(sources)} production Swift files and {control_count} Button/Menu/ButtonStyle controls."
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
