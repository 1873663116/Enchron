#!/usr/bin/env python3
"""Assign every reachability cell to a journey step, a declared exemption, or a gap.

The reachability matrix answers whether an operation can be delivered. It says
nothing about whether anything checks what the operation did. The journey suite
answers that, but it is prose, so "this is covered elsewhere" was unfalsifiable
until the two were joined on the same key.

The join key is the cell, not the operation. The same menu in window and in
panorama are two cells, and a journey that tours presentations usually exercises
only one of them.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = REPOSITORY_ROOT / "Config/reachability_matrix_baseline.json"
LEDGER_PATH = REPOSITORY_ROOT / "Config/journey_operation_coverage.json"

# (context pattern, operation pattern) -> assignment. First match wins, so put
# exceptions above the family rule they carve out of.
ASSIGNMENTS: tuple[tuple[str, str, dict[str, object]], ...] = (
    # --- harness verbs: not product operations, they drive the journeys ---
    (r".*", r"^command:", {"status": "harness"}),
    (r".*", r"^scroll:emby$", {"journey": "J04", "step": 4}),
    (r".*", r"^scroll:file-list$", {"status": "gap"}),
    (r".*", r"^negative:", {"status": "harness"}),

    # --- system-domain entries: human layer, once per wearer session ---
    (r".*", r"SourcesSidebar-add(Files|Folder|Photos)$", {"status": "manual"}),
    (r".*", r"MediaLibrary-Manage-add(Files|Folder|Photos)$", {"status": "manual"}),

    # --- navigation ---
    (r".*", r"Navigation-Ornament-tab-(files|settings)$", {"primitive": "P1"}),
    (r".*", r"Navigation-Ornament-tab-environment$", {"status": "gap"}),

    # --- Emby ---
    (r".*", r"Emby-Connection-", {"journey": "J04", "step": 2}),
    (r".*", r"Emby-Navigation-Tab$", {"primitive": "P1"}),
    (r".*", r"Emby-(PosterCard|Episode|StillCard)-", {"journey": "J04", "step": 4}),
    (r".*", r"Emby-(Detail-Overview-Expand|Detail-Version|Library-Sort"
            r"|Search-Field|Season-Picker|Season-|SignOut)", {"status": "gap"}),
    (r".*", r"Emby-Detail-", {"status": "gap"}),

    # --- source connection forms ---
    (r".*", r"SourceConnection-webDAV-", {"journey": "J02", "step": 3}),
    (r".*", r"SourceConnection-smb-", {"journey": "J03", "step": 3}),
    (r".*", r"SourcesSidebar-addWebDAV$", {"journey": "J02", "step": 2}),
    (r".*", r"SourcesSidebar-addSMB$", {"journey": "J03", "step": 2}),
    (r".*", r"SourcesSidebar-sourceMore$", {"journey": "J02", "step": 2}),
    (r".*", r"SourcesSidebar-source-", {"journey": "J02", "step": 6}),
    (r".*", r"SourcesSidebar-(delete|refresh)$", {"status": "gap"}),
    (r".*", r"CertificateTrust-trust$", {"journey": "J02", "step": "4b"}),
    (r".*", r"CertificateTrust-cancel$", {"status": "gap"}),

    # --- library browsing chrome ---
    (r".*", r"FileBrowsing-grid-(folder|video)-", {"journey": "J02", "step": 7}),
    (r".*", r"FileBrowsing-Manage-button$", {"journey": "J11", "step": 2}),
    (r".*", r"FileBrowsing-FilesScreen-(search|sort|viewMode|sidebarToggle"
            r"|navBackForward-)", {"status": "gap"}),
    (r".*", r"(FileBrowsing|MediaLibrary)-Breadcrumb-current$", {"status": "gap"}),
    (r".*", r"FileBrowsing-error-", {"status": "gap"}),

    # --- media library management ---
    (r".*", r"MediaLibrary-Manage-newFolder$", {"journey": "J11", "step": 2}),
    (r".*", r"MediaLibrary-NewFolder-", {"journey": "J11", "step": 2}),
    (r".*", r"MediaLibrary-RenameFolder-", {"journey": "J11", "step": 3}),
    (r".*", r"MediaLibrary-Manage-selectMultiple$", {"journey": "J11", "step": 5}),
    (r".*", r"MediaLibrary-MultiSelect-(move|done)$", {"journey": "J11", "step": 5}),
    (r".*", r"MediaLibrary-MultiSelect-(delete|confirmDelete)$",
     {"journey": "J11", "step": 7}),
    (r".*", r"MediaLibrary-grid-(folder|video)-", {"journey": "J11", "step": 4}),
    (r".*", r"MediaLibrary-error-dismiss$", {"journey": "J12", "step": 5}),

    # --- settings ---
    (r".*", r"Settings-category-", {"journey": "J10", "step": 7}),
    (r".*", r"^menu:settings:resume-strategy$", {"journey": "J10", "step": 7}),
    (r".*", r"^menu:settings:default-speed$", {"journey": "J10", "step": 9}),
    (r".*", r"^menu:settings:controls-auto-hide$", {"journey": "J10", "step": 10}),
    (r".*", r"^menu:settings:default-scenic-environment$",
     {"journey": "J10", "step": 11}),
    (r".*", r"^menu:settings:end-behavior$", {"journey": "J10", "step": 12}),

    # --- environment card: only its residency and blocking are journeyed ---
    (r".*", r"EnvironmentCard-card$", {"journey": "J07", "step": "5a"}),
    (r".*", r"EnvironmentCard-(carousel|button-environment-|effect-)",
     {"status": "gap"}),

    # --- playback chrome, per presentation ---
    (r"^window$", r"PlayerUI-TopAction-videoFormat$", {"journey": "J07", "step": 4}),
    (r"^window$", r"PlayerUI-TopAction-dock$", {"primitive": "P6"}),
    (r"^window$", r"PlayerUI-TopAction-more$", {"journey": "J07", "step": 3}),
    (r"^portal$", r"PlayerUI-TopAction-resumePanorama$", {"primitive": "P7"}),
    (r"^window$", r"PlayerUI-DockMenu-", {"primitive": "P6"}),
    (r".*", r"PlayerUI-InfoBar-button-back$", {"journey": "J01", "step": 11}),
    (r"^window$", r"PlayerUI-VideoFormat-(apply|cancel)$", {"journey": "J07", "step": 4}),
    (r"^window$", r"PlayerUI-VideoFormat-\{title\}", {"primitive": "P7"}),
    (r"^window$", r"PlayerUI-VideoFormat-CustomAngle$", {"journey": "J06", "step": 5}),
    (r"^window$", r"PlayerUI-VideoFormat-HDRFallback$", {"journey": "J05", "step": 2}),
    (r"^window$", r"PlayerUI-VideoFormat-automatic$", {"status": "gap"}),
    (r"^window$", r"PlayerUI-menu-(audio|subtitles)$", {"primitive": "P12"}),
    (r"^window$", r"PlayerUI-menu-(episodes|speed)$", {"status": "gap"}),
    # Portal carries the same chrome as window and J07 only passes through it.
    (r"^portal$", r"PlayerUI-(TopAction|VideoFormat|menu)-", {"status": "gap"}),
    (r".*", r"^environmentVolume:", {"status": "gap"}),
    (r".*", r"PlayerUI-loadFailure-", {"journey": "J09", "step": 3}),
    (r".*", r"PlayerUI-playbackIssue-confirm$", {"journey": "J12", "step": 5}),
    (r".*", r"PlayerUI-unmetCapability-dismiss$", {"status": "gap"}),
    (r".*", r"PlayerUI-spatialFailure-", {"status": "gap"}),
    (r".*", r"PlayerUI-presentation-conversion-dismiss$", {"status": "gap"}),
    (r".*", r"PlayerUI-resumeDecision-", {"journey": "J10", "step": 7}),

    (r"^docked$", r"PlayerPanel-media-information-close$",
     {"journey": "J07", "step": 6}),
    (r"^docked$", r"PlayerPanel-menu-more$", {"journey": "J07", "step": 6}),
    (r"^docked$", r"PlayerPanel-button-exit-spatial$", {"journey": "J07", "step": 7}),
    (r".*", r"PlayerPanel-media-information-close$", {"status": "gap"}),
    (r".*", r"PlayerPanel-menu-(audio|subtitles|more|episodes|speed)$",
     {"status": "gap"}),
    (r".*", r"PlayerPanel-menu-\{category\}", {"status": "gap"}),
    (r".*", r"PlayerPanel-button-(play|rewind|forward|settings)$", {"status": "gap"}),
    (r".*", r"PlayerPanel-(progress|precision-timeline)$", {"status": "gap"}),
    (r".*", r"PlayerPanel-\{identifier\}-slider$", {"status": "gap"}),
    (r".*", r"PlayerPanel-DockedPlacement-reset$", {"status": "gap"}),
    (r".*", r"PlayerPanel-button-exit-spatial$", {"status": "gap"}),
)

REASONS = {
    "harness": "取证通道动词，不是产品操作",
    "manual": "系统面板，人工层每场次各走一遍",
    "gap": "可送达，但没有任何旅程步骤检查它做了什么",
}


def assign(context: str, operation: str) -> dict[str, object]:
    for context_pattern, operation_pattern, result in ASSIGNMENTS:
        if re.search(context_pattern, context) and re.search(operation_pattern, operation):
            return dict(result)
    return {"status": "unassigned"}


def main() -> int:
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    entries = []
    for cell in matrix["cells"]:
        entry = {"context": cell["context"], "operation": cell["operation"]}
        entry.update(assign(cell["context"], cell["operation"]))
        if entry.get("status") in REASONS:
            entry["reason"] = REASONS[entry["status"]]
        entries.append(entry)

    entries.sort(key=lambda e: (e["context"], e["operation"]))
    LEDGER_PATH.write_text(
        json.dumps(
            {"schemaVersion": 1, "generatedFrom": MATRIX_PATH.name, "cells": entries},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    tally: dict[str, int] = {}
    for entry in entries:
        key = entry.get("status") or f"journey:{entry.get('journey') or entry.get('primitive')}"
        tally[key] = tally.get(key, 0) + 1
    verified = sum(v for k, v in tally.items() if k.startswith("journey:"))
    print(f"格数 {len(entries)}")
    print(f"  有旅程步骤检查其效果: {verified}")
    for key in sorted(k for k in tally if not k.startswith("journey:")):
        print(f"  {key}: {tally[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
