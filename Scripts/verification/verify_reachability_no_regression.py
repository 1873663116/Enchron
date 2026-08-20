#!/usr/bin/env python3
"""Prove selected accepted reachability cells were not changed by round 14."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REFERENCE = "19a817f9"

FILES_SCREEN = "Apps/Enchron/Screens/FilesScreen.swift"
EMBY_SCREENS = "Modules/Emby/EmbyScreens.swift"
MAIN_VIEW = "Apps/Enchron/MainView.swift"
PLAYBACK_PANEL = "Modules/PlaybackPresentation/Views/PlaybackPanel.swift"

COVERED_CELLS = (
    ("main-window-browser", "accessibility:Emby-Season-Picker"),
    (
        "main-window-browser",
        "accessibility:Emby-Season-{season.metadata.id.rawValue}",
    ),
    ("main-window-browser", "accessibility:MediaLibrary-error-dismiss"),
    ("portal", "accessibility:PlayerUI-unmetCapability-dismiss"),
    ("docked", "accessibility:PlayerPanel-menu-more"),
)


def git(*arguments: str) -> str:
    completed = subprocess.run(
        ("git", *arguments),
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def source_at(revision: str, path: str) -> str:
    return git("show", f"{revision}:{path}")


def source_now(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def exact_region(source: str, start: str, end: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    return source[start_index:end_index]


def normalized(source: str) -> str:
    return " ".join(source.split())


def digest(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def record_exact_check(
    checks: list[dict[str, Any]],
    *,
    name: str,
    reference_source: str,
    current_source: str,
) -> None:
    passed = reference_source == current_source
    checks.append({
        "name": name,
        "passed": passed,
        "referenceSha256": digest(reference_source),
        "currentSha256": digest(current_source),
    })


def build_evidence(reference: str) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    current_revision = git("rev-parse", "HEAD").strip()
    reference_revision = git("rev-parse", reference).strip()

    for path in (FILES_SCREEN, EMBY_SCREENS):
        record_exact_check(
            checks,
            name=f"unchanged-file:{path}",
            reference_source=source_at(reference_revision, path),
            current_source=source_now(path),
        )

    reference_panel = source_at(reference_revision, PLAYBACK_PANEL)
    current_panel = source_now(PLAYBACK_PANEL)
    for name, start, end in (
        (
            "player-panel-more-control",
            "    private var moreMenu: some View {",
            "    /// 逐帧步进",
        ),
        (
            "player-panel-more-product-handler",
            "    private func liveMoreMenuSections(_ live: FusedPlayerPanelLive) -> some View {",
            "    @ViewBuilder\n    private func liveMenuItems",
        ),
    ):
        record_exact_check(
            checks,
            name=name,
            reference_source=exact_region(reference_panel, start, end),
            current_source=exact_region(current_panel, start, end),
        )

    reference_main = normalized(source_at(reference_revision, MAIN_VIEW))
    current_main = normalized(source_now(MAIN_VIEW))
    shared_mapping = 'case .playerDeck: "PlayerUI-unmetCapability-dismiss"'
    old_action_tokens = (
        'case .confirm: Button("OK", role: .cancel) {',
        "recordReachability(action)",
        "playbackRuntime.setUserVisibleIssue(nil)",
        ".accessibilityIdentifier(confirmActionIdentifier)",
    )
    current_action_tokens = (
        'case .confirm: Button("OK", role: .cancel) {',
        "recordReachability(action, at: location)",
        "playbackRuntime.setUserVisibleIssue(nil)",
        ".accessibilityIdentifier(confirmActionIdentifier(at: location))",
    )
    current_location_adapter = normalized(
        """
        func playbackIssueAlert(
            at location: PlaybackIssuePresentationLocation,
            onRetry: @escaping () -> Void = {},
            onClose: @escaping () -> Void = {}
        ) -> some View {
            playbackIssueAlert(
                in: .location(location),
                onRetry: onRetry,
                onClose: onClose
            )
        }
        """
    )
    portal_checks = {
        "referenceIdentifierMapping": shared_mapping in reference_main,
        "currentIdentifierMapping": shared_mapping in current_main,
        "referenceConfirmAction": all(token in reference_main for token in old_action_tokens),
        "currentConfirmAction": all(token in current_main for token in current_action_tokens),
        "currentLocationAdapter": current_location_adapter in current_main,
    }
    checks.append({
        "name": "portal-unmet-capability-action-semantics",
        "passed": all(portal_checks.values()),
        "conditions": portal_checks,
    })

    product_paths = (FILES_SCREEN, EMBY_SCREENS, MAIN_VIEW, PLAYBACK_PANEL)
    dirty_product_paths = git("status", "--porcelain", "--", *product_paths).splitlines()
    checks.append({
        "name": "product-sources-have-no-working-tree-edits",
        "passed": not dirty_product_paths,
        "paths": list(product_paths),
        "dirtyEntries": dirty_product_paths,
    })

    return {
        "schemaVersion": 1,
        "status": "passed" if all(check["passed"] for check in checks) else "failed",
        "referenceRevision": reference_revision,
        "currentRevision": current_revision,
        "checks": checks,
        "cells": [
            {"context": context, "operation": operation}
            for context, operation in COVERED_CELLS
        ],
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", default=DEFAULT_REFERENCE)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    evidence = build_evidence(arguments.reference)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
