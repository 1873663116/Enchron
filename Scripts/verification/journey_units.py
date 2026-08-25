#!/usr/bin/env python3
"""The operation units the regression suite is driven in, and the checks that
keep their coverage claims honest.

A unit is the smallest chunk of device driving that ends in a verdict. It is not
a single tap: `library.new-folder` opens the manage menu, taps New Folder, types
a name and confirms, then checks the folder is on the grid. One invocation, one
verdict, a few seconds. The agent reads the verdict and picks the next unit.
That granularity is the whole point. Single verbs make the agent spend ten round
trips to learn nothing; a whole-suite script makes it wait an hour to learn one
bit.

Coverage is derived from what a step drives. A step that taps an identifier
covers the inventory operation that identifier belongs to, in the presentation
the step runs in, and it says so by tapping it. Only the operations no target
string can express are declared: a menu opening, a scroll, an environment volume
round trip, an absence asserted. Declaring anything else is rejected, because a
second copy of a fact can only ever drift from the first. Setup and evidence
steps cover nothing; reaching a screen and reading it back are not the operation.

The axes are the source-derived inventory, so an operation added to the product
is uncovered the moment it exists, not after someone remembers to widen a table.
Every cell is either covered by a step or carries a written exemption, and an
exemption for a cell that turns out to be covered fails as loudly as a gap.

Drive mode is also per step. `injected` means the step reaches into the app
instead of touching it, and it must say why, what layer it skips, and which
class of defect is therefore invisible at that step. A settings menu whose host
reported not hittable for months is what that field is for.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import json
from pathlib import Path
import re
import sys

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
INVENTORY_PATH = REPOSITORY_ROOT / "Config/reachability_operation_inventory.json"
LEDGER_PATH = REPOSITORY_ROOT / "Config/journey_operation_coverage.json"
REFERENCE_PATH = (
    REPOSITORY_ROOT
    / ".agents/skills/vp-e2e/references/operation-units.md"
)

REAL = "real"
INJECTED = "injected"
SETUP = "setup"
EVIDENCE = "evidence"
WEARER = "wearer"
DEVICE_HUB = "device-hub"
DRIVES = (REAL, INJECTED, SETUP, EVIDENCE, WEARER, DEVICE_HUB)

VERBS = (
    "tap",
    "doubleTap",
    "tapSequence",
    "type",
    "swipeUp",
    "swipeDown",
    "swipeLeft",
    "swipeRight",
    "snapshot",
    "relaunch",
    "app",
    "settle",
    "assert",
    "frames",
    "handoff",
    "pinch",
)

COMMAND_CHANNEL_PATH = REPOSITORY_ROOT / "Apps/Enchron/TestCommandChannel.swift"

ENTITY_INPUT_HOSTS = frozenset({"windowPlaybackSurfaceEntityTapTarget"})


def app_commands() -> set[str]:
    """The verbs the app's command channel answers, read from the channel itself.

    A unit naming a verb the app does not have fails on the device, several
    minutes into a session, as a response the runner cannot explain. Reading the
    dispatcher makes it a local failure instead.
    """
    source = COMMAND_CHANNEL_PATH.read_text(encoding="utf-8")
    body = source[source.index('case "ping":') : source.index("case \"screenSize\":")]
    return set(re.findall(r'case "([A-Za-z]+)"', body))


@dataclass(frozen=True)
class Injection:
    """Why a step reaches into the app instead of touching it."""

    why: str
    skips: str
    blind: str


@dataclass(frozen=True)
class Step:
    verb: str
    target: str = ""
    drive: str = REAL
    context: str = ""
    covers: tuple[str, ...] = ()
    expect: str = ""
    label: str | None = None
    index: int | None = None
    text: str | None = None
    args: tuple[str, ...] = ()
    identifiers: tuple[str, ...] = ()
    injection: Injection | None = None
    entity: str = ""
    probe: str = ""

    def targets(self) -> tuple[str, ...]:
        if self.identifiers:
            return self.identifiers
        return (self.target,) if self.target else ()

    def contexts(self, unit_contexts: tuple[str, ...]) -> tuple[str, ...]:
        """Where this step actually lands.

        A unit that crosses presentations mid-way, entering panorama from the
        portal, runs its later steps against a different host than the one it
        started in. Those steps name the context they cross into, and everything
        after the crossing is credited there.
        """
        return (self.context,) if self.context else unit_contexts

    def claims(self, unit_contexts: tuple[str, ...]) -> list[tuple[str, str]]:
        return [
            (context, entry)
            for entry in self.covers
            for context in self.contexts(unit_contexts)
        ]


@dataclass(frozen=True)
class Unit:
    """One chunk of driving that ends in a verdict.

    A unit naming several contexts is run once per context. The same control in
    window and in panorama is two cells of the matrix because it is two hit
    tests against two different hosts, and a pass in one says nothing about the
    other. Listing both here prices that honestly instead of claiming one run
    covered both.
    """

    id: str
    title: str
    contexts: tuple[str, ...]
    precondition: str
    proves: str
    steps: tuple[Step, ...] = ()
    needs: tuple[str, ...] = field(default=tuple())


def real(verb: str, target: str = "", **kwargs: object) -> Step:
    return Step(verb=verb, target=target, drive=REAL, **kwargs)  # type: ignore[arg-type]


def setup(verb: str, target: str = "", **kwargs: object) -> Step:
    return Step(verb=verb, target=target, drive=SETUP, **kwargs)  # type: ignore[arg-type]


def evidence(verb: str, target: str = "", **kwargs: object) -> Step:
    return Step(verb=verb, target=target, drive=EVIDENCE, **kwargs)  # type: ignore[arg-type]


def wearer(target: str, expect: str, covers: tuple[str, ...] = ()) -> Step:
    return Step(
        verb="handoff", target=target, drive=WEARER, expect=expect, covers=covers
    )


def injected(
    verb: str, target: str, why: str, skips: str, blind: str, **kwargs: object
) -> Step:
    return Step(
        verb=verb,
        target=target,
        drive=INJECTED,
        injection=Injection(why=why, skips=skips, blind=blind),
        **kwargs,  # type: ignore[arg-type]
    )


def device_hub(
    verb: str, target: str, *, entity: str, probe: str, **kwargs: object
) -> Step:
    return Step(
        verb=verb,
        target=target,
        drive=DEVICE_HUB,
        entity=entity,
        probe=probe,
        **kwargs,
    )


CONTROLS_ARE_SPATIAL = dict(
    why="Panorama and Docked put the playback controls on a RealityKit collision "
    "body, and a synthetic touch never reaches one. Nothing in the app can be "
    "driven in those presentations until the controls are on screen.",
    skips="The summon gesture itself: hit test against the collision body and "
    "the tap gesture recogniser attached to it.",
    blind="A regression that stops the video surface from accepting the summon "
    "tap looks identical to a pass at this step. The controls it reveals are "
    "still tapped for real afterwards.",
)

FAULT_HAS_NO_PRODUCT_PATH = dict(
    why="The product has no user operation that forces this failure on demand, "
    "and the real cause is a remote server or a decoder refusing content.",
    skips="Whatever real chain would have produced the fault.",
    blind="Any defect in detecting the fault. Only the presentation of an "
    "already-detected fault is under test here.",
)

FIXTURE = "sdr-bframe-aggregate-30s.mkv"
FIXTURE_CARD = f"MediaLibrary-grid-video-{FIXTURE}"
FOLDER = "Journey Fixture"

UNITS: tuple[Unit, ...] = (
    Unit(
        id="session.open",
        title="Bring up a session and prove the evidence channel round-trips",
        contexts=("main-window-browser",),
        precondition="Device connected, no other runner resident.",
        proves="Commands reach the app and the probe file comes back unchanged.",
        steps=(
            setup("app", "ping", expect="Runner answers with the current session id."),
            evidence(
                "app", "probeStatus", expect="Probe file writes and reads back intact."
            ),
        ),
    ),
    Unit(
        id="library.reset",
        title="Empty the library and land on a named folder",
        contexts=("main-window-browser",),
        precondition="Session open.",
        proves="Every unit after this starts from the same library state.",
        steps=(
            setup(
                "app",
                "resetState",
                args=(f"libraryFolder={FOLDER}",),
                expect="Library holds no references and exactly one folder.",
            ),
            setup("app", "listLibrary", expect="Reference list is empty."),
        ),
    ),
    Unit(
        id="library.import",
        title="Import a file through the manage menu",
        contexts=("main-window-browser",),
        precondition="library.reset done and the file staged in TestMediaInbox.",
        proves="The in-app import entry opens the system picker.",
        needs=("library.reset",),
        steps=(
            real(
                "tap",
                "FileBrowsing-Manage-button",
                expect="Manage menu opens.",
            ),
            real(
                "tap",
                "MediaLibrary-Manage-addFiles",
                expect="System file picker appears.",
            ),
            wearer(
                "system file picker",
                "Wearer picks the fixture. The picker is a system scene; XCTest "
                "cannot reach it.",
            ),
            injected(
                "app",
                "importMedia",
                args=(f"file={FIXTURE}",),
                expect="Reference list contains the fixture.",
                **{
                    **FAULT_HAS_NO_PRODUCT_PATH,
                    "why": "The system file picker is out of XCTest's reach, so an "
                    "unattended run has no way to complete the import the two real "
                    "taps above started.",
                    "skips": "The picker and the file selection inside it.",
                    "blind": "Any defect between picking a file and the library "
                    "accepting it. The taps that open the picker are real and are "
                    "checked above.",
                },
            ),
        ),
    ),
    Unit(
        id="library.import-entries",
        title="Every import entry opens its picker",
        contexts=("main-window-browser",),
        precondition="Files tab, manage menu reachable.",
        proves="Folder import entries are reachable, not only Files.",
        steps=(
            real(
                "tap",
                "FileBrowsing-Manage-button",
                expect="Manage menu opens.",
            ),
            real(
                "tap",
                "MediaLibrary-Manage-addFolder",
                expect="Folder picker appears.",
            ),
            wearer("system folder picker", "Wearer cancels."),
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-addFiles",
                expect="Sidebar file entry opens the same picker.",
            ),
            wearer("system file picker", "Wearer cancels."),
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-addFolder",
                expect="Sidebar folder entry opens the folder picker.",
            ),
            wearer("system folder picker", "Wearer cancels."),
        ),
    ),
    Unit(
        id="library.new-folder",
        title="Create a folder and enter it",
        contexts=("main-window-browser",),
        precondition="library.reset done.",
        proves="Folder creation, naming, and breadcrumb navigation.",
        needs=("library.reset",),
        steps=(
            real(
                "tap",
                "FileBrowsing-Manage-button",
                expect="Manage menu opens.",
            ),
            real(
                "tap",
                "MediaLibrary-Manage-newFolder",
                expect="Naming sheet appears.",
            ),
            real(
                "tap",
                "MediaLibrary-NewFolder-cancel",
                expect="Sheet closes and no folder is created.",
            ),
            real(
                "tap",
                "FileBrowsing-Manage-button",
                expect="Manage menu opens again.",
            ),
            real(
                "tap",
                "MediaLibrary-Manage-newFolder",
                expect="Naming sheet appears again.",
            ),
            real(
                "type",
                "MediaLibrary-NewFolder-name",
                label="Folder name",
                text="Unit Folder",
                expect="Field holds the typed name. SwiftUI drops the "
                "identifier from a TextField inside an alert, so the label is "
                "the handle that resolves.",
            ),
            real(
                "tap",
                "MediaLibrary-NewFolder-create",
                expect="Sheet closes and the folder is on the grid.",
            ),
            real(
                "tap",
                "MediaLibrary-grid-folder-Unit Folder",
                expect="Grid shows the folder contents.",
            ),
            real(
                "tap",
                "MediaLibrary-Breadcrumb-current",
                expect="Grid returns to the library root.",
            ),
        ),
    ),
    Unit(
        id="library.rename-folder",
        title="Rename a folder",
        contexts=("main-window-browser",),
        precondition="A folder exists on the grid.",
        proves="Rename reaches persistence and the grid follows.",
        needs=("library.new-folder",),
        steps=(
            real(
                "tap",
                "MediaLibrary-RenameFolder-cancel",
                expect="Sheet closes and the folder keeps its name.",
            ),
            real(
                "tap",
                "MediaLibrary-grid-folder-Unit Folder",
                expect="Rename is reopened from the folder's own menu.",
            ),
            real(
                "type",
                "MediaLibrary-RenameFolder-name",
                label="Folder name",
                text="Renamed Folder",
                expect="Field holds the new name. The alert focuses the field "
                "on appearance, and its identifier does not survive the alert, "
                "so the label is the handle that resolves.",
            ),
            real(
                "tap",
                "MediaLibrary-RenameFolder-confirm",
                expect="Grid shows the new name.",
            ),
            evidence(
                "app", "listLibrary", expect="Persisted folder list shows the new name."
            ),
        ),
    ),
    Unit(
        id="library.multi-select-move",
        title="Select several items and move them into a folder",
        contexts=("main-window-browser",),
        precondition="At least one video and one folder in the library.",
        proves="Multi-select mode, move, and exit.",
        needs=("library.import", "library.new-folder"),
        steps=(
            real(
                "tap",
                "FileBrowsing-Manage-button",
                expect="Manage menu opens.",
            ),
            real(
                "tap",
                "MediaLibrary-Manage-selectMultiple",
                expect="Grid enters selection mode.",
            ),
            real(
                "tap",
                FIXTURE_CARD,
                expect="Card shows as selected instead of opening playback.",
            ),
            real(
                "tap",
                "MediaLibrary-MultiSelect-move",
                expect="Destination picker appears.",
            ),
            real(
                "tap",
                "MediaLibrary-MultiSelect-done",
                expect="Selection mode ends.",
            ),
        ),
    ),
    Unit(
        id="library.multi-select-delete",
        title="Delete selected items with confirmation",
        contexts=("main-window-browser",),
        precondition="At least one video in the library.",
        proves="Delete is confirmed before it takes effect.",
        needs=("library.import",),
        steps=(
            real("tap", "FileBrowsing-Manage-button", expect="Manage menu opens."),
            real(
                "tap",
                "MediaLibrary-Manage-selectMultiple",
                expect="Grid enters selection mode.",
            ),
            real("tap", FIXTURE_CARD, expect="Card is selected."),
            real(
                "tap",
                "MediaLibrary-MultiSelect-delete",
                expect="Confirmation appears and nothing is deleted yet.",
            ),
            real(
                "tap",
                "MediaLibrary-MultiSelect-confirmDelete",
                expect="Item leaves the grid and the reference list.",
            ),
            evidence("app", "listLibrary", expect="Reference is gone."),
        ),
    ),
    Unit(
        id="library.error-surface",
        title="A library error can be read and dismissed",
        contexts=("main-window-browser",),
        precondition="Files tab.",
        proves="The error surface appears and its dismiss control works.",
        steps=(
            injected(
                "app",
                "showFileBrowserError",
                expect="Error surface appears.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "MediaLibrary-error-dismiss",
                expect="Error surface closes.",
            ),
            injected(
                "app",
                "showFileBrowserError",
                expect="Error surface appears again with actions.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "FileBrowsing-error-primary",
                expect="Primary action runs.",
            ),
            injected(
                "app",
                "showFileBrowserError",
                expect="Error surface appears again.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "FileBrowsing-error-secondary",
                expect="Secondary action runs.",
            ),
            injected(
                "app",
                "setFileBrowserAlertField",
                expect="Alert field is populated for the next assertion.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
        ),
    ),
    Unit(
        id="files.chrome",
        title="Search, sort, view mode, sidebar and history controls",
        contexts=("main-window-browser",),
        precondition="Files tab with content on the grid.",
        proves="Every browser chrome control does what it claims.",
        needs=("library.import",),
        steps=(
            real(
                "tap",
                "FileBrowsing-FilesScreen-search",
                expect="Search field takes focus.",
            ),
            real(
                "type",
                "FileBrowsing-FilesScreen-search",
                text="aggregate",
                expect="Grid narrows to matching items.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-sort",
                expect="Sort options appear.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-sort-modifiedDate",
                expect="Grid re-sorts by modified date and the row is checked.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-viewMode",
                expect="Grid switches between layouts.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-sidebarToggle",
                expect="Sidebar hides and shows.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-navBackForward-back",
                expect="Browser returns to the previous location.",
            ),
            real(
                "tap",
                "FileBrowsing-FilesScreen-navBackForward-forward",
                expect="Browser returns forward.",
            ),
            real(
                "swipeUp",
                "FileBrowsing-FilesScreen-search",
                covers=("scroll:file-list",),
                expect="File list scrolls. The identifier is mandatory: a bare "
                "swipe degrades to the Application element and tears the session "
                "down.",
            ),
        ),
    ),
    Unit(
        id="files.sources-sidebar",
        title="Source rows, their menu, refresh and delete",
        contexts=("main-window-browser",),
        precondition="At least one remote source configured.",
        proves="A source can be selected, refreshed and removed.",
        needs=("source.webdav",),
        steps=(
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-source-{item.id}",
                label="WebDAV Unit",
                expect="Source is selected. Three elements share this identifier, "
                "so the row is selected by label, not by identifier.",
            ),
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-sourceMore",
                expect="Source menu opens.",
            ),
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-refresh",
                expect="Source listing reloads.",
            ),
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-delete",
                expect="Source leaves the sidebar.",
            ),
        ),
    ),
    Unit(
        id="source.webdav",
        title="Connect a WebDAV source, including certificate trust",
        contexts=("main-window-browser",),
        precondition="library.reset done so the remembered certificate is cleared.",
        proves="The whole connection form is drivable and trust is asked once.",
        needs=("library.reset",),
        steps=(
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-addWebDAV",
                expect="Connection form appears.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-webDAV-name",
                text="WebDAV Unit",
                expect="Name field holds the value.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-webDAV-address",
                text="${WEBDAV_ADDRESS}",
                expect="Address field holds the value.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-webDAV-username",
                text="${WEBDAV_USERNAME}",
                expect="Username field holds the value.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-webDAV-password",
                text="${WEBDAV_PASSWORD}",
                expect="Password field is filled and never echoed into the log.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-webDAV-connect",
                expect="Connection is attempted.",
            ),
            real(
                "tap",
                "FileBrowsing-CertificateTrust-trust",
                expect="Certificate is accepted and the listing loads.",
            ),
            real(
                "tap",
                "FileBrowsing-grid-folder-{folder.name}",
                label="Samples",
                expect="Remote folder opens.",
            ),
            real(
                "tap",
                "FileBrowsing-Breadcrumb-current",
                expect="Browser returns up one level.",
            ),
        ),
    ),
    Unit(
        id="source.webdav-refused",
        title="Refusing the certificate leaves the source unconnected",
        contexts=("main-window-browser",),
        precondition="No remembered certificate for the host.",
        proves="Cancel on the trust prompt is a real decision, not a no-op.",
        needs=("library.reset",),
        steps=(
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-addWebDAV",
                expect="Connection form appears.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-webDAV-address",
                text="${WEBDAV_ADDRESS}",
                expect="Address field holds the value.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-webDAV-connect",
                expect="Trust prompt appears.",
            ),
            real(
                "tap",
                "FileBrowsing-CertificateTrust-cancel",
                expect="No source is added and no listing loads.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-webDAV-cancel",
                expect="Form closes with nothing added.",
            ),
        ),
    ),
    Unit(
        id="source.smb",
        title="Connect an SMB share, credentialed and as guest",
        contexts=("main-window-browser",),
        precondition="library.reset done.",
        proves="The SMB form including the guest toggle is drivable.",
        needs=("library.reset",),
        steps=(
            real(
                "tap",
                "FileBrowsing-SourcesSidebar-addSMB",
                expect="SMB form appears.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-smb-name",
                text="SMB Unit",
                expect="Name field holds the value.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-smb-address",
                text="${SMB_ADDRESS}",
                expect="Address field holds the value.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-smb-guest",
                expect="Credential fields disable when guest is on.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-smb-guest",
                expect="Credential fields enable again when guest is off.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-smb-username",
                text="${SMB_USERNAME}",
                expect="Username field holds the value.",
            ),
            real(
                "type",
                "FileBrowsing-SourceConnection-smb-password",
                text="${SMB_PASSWORD}",
                expect="Password field is filled and never echoed into the log.",
            ),
            real(
                "tap",
                "FileBrowsing-SourceConnection-smb-connect",
                expect="Share mounts and its listing loads.",
            ),
            real(
                "tap",
                "FileBrowsing-grid-video-{file.name}",
                label=FIXTURE,
                expect="Remote file opens into playback.",
            ),
        ),
    ),
    Unit(
        id="source.smb-cancel",
        title="Cancelling the SMB form adds nothing",
        contexts=("main-window-browser",),
        precondition="Files tab.",
        proves="Cancel discards the form.",
        steps=(
            real("tap", "FileBrowsing-SourcesSidebar-addSMB", expect="Form appears."),
            real(
                "tap",
                "FileBrowsing-SourceConnection-smb-cancel",
                expect="Form closes and the sidebar is unchanged.",
            ),
        ),
    ),
    Unit(
        id="navigation.tabs",
        title="Move between the three tabs",
        contexts=("main-window-browser",),
        precondition="Session open.",
        proves="Each tab is reachable and the content region follows.",
        steps=(
            real(
                "tap",
                "Navigation-Ornament-tab-files",
                expect="Files screen is on screen.",
            ),
            real(
                "tap",
                "Navigation-Ornament-tab-settings",
                expect="Settings screen is on screen.",
            ),
            real(
                "tap",
                "Navigation-Ornament-tab-environment",
                expect="Environment screen is on screen.",
            ),
            real(
                "tap",
                "Navigation-Ornament-tab-files",
                expect="Files screen is on screen again.",
            ),
        ),
    ),
    Unit(
        id="settings.categories",
        title="Each settings category shows its own detail",
        contexts=("main-window-browser",),
        precondition="Settings tab.",
        proves="Selecting a category swaps the detail pane, not just the "
        "selection highlight.",
        steps=(
            real(
                "tap",
                "Settings-category-playback",
                expect="Detail pane shows playback settings. A delivered tap "
                "whose detail pane does not follow is the defect this step "
                "exists to catch.",
            ),
            real(
                "tap",
                "Settings-category-storagePrivacy",
                expect="Detail pane shows storage and privacy.",
            ),
            real(
                "tap", "Settings-category-about", expect="Detail pane shows About."
            ),
        ),
    ),
    Unit(
        id="settings.menus",
        title="Every settings menu opens by touch and its choice sticks",
        contexts=("main-window-browser",),
        precondition="Settings tab, playback category.",
        proves="The menu host takes a real tap, the item list renders, and the "
        "chosen value persists across a relaunch.",
        steps=(
            real("tap", "Settings-category-playback", expect="Playback detail shows."),
            real(
                "tap",
                "Settings-menu-resume-strategy",
                covers=("menu:settings:resume-strategy",),
                expect="Resume strategy menu opens with its items in the "
                "hierarchy.",
            ),
            real(
                "tap",
                "Settings-menuOption-resume-strategy-askEveryTime",
                expect="Menu closes and the row shows the chosen value.",
            ),
            real(
                "tap",
                "Settings-menu-default-speed",
                covers=("menu:settings:default-speed",),
                expect="Default speed menu opens.",
            ),
            real(
                "tap",
                "Settings-menuOption-default-speed-1.25",
                expect="Row shows the chosen speed.",
            ),
            real(
                "tap",
                "Settings-menu-controls-auto-hide",
                covers=("menu:settings:controls-auto-hide",),
                expect="Auto-hide menu opens.",
            ),
            real(
                "tap",
                "Settings-menuOption-controls-auto-hide-never",
                expect="Row shows the chosen value.",
            ),
            real(
                "tap",
                "Settings-menu-default-scenic-environment",
                covers=("menu:settings:default-scenic-environment",),
                expect="Environment menu opens.",
            ),
            real(
                "tap",
                "Settings-menuOption-default-scenic-environment-{environment.rawValue}",
                label="Mount Hood",
                expect="Row shows the chosen value.",
            ),
            real(
                "tap",
                "Settings-menu-end-behavior",
                covers=("menu:settings:end-behavior",),
                expect="End behaviour menu opens.",
            ),
            real(
                "tap",
                "Settings-menuOption-end-behavior-playNext",
                expect="Row shows the chosen value.",
            ),
            setup("relaunch", expect="App restarts."),
            evidence(
                "snapshot",
                "Settings-menu-default-speed",
                expect="Every chosen value survived the relaunch.",
            ),
        ),
    ),
    Unit(
        id="settings.actions",
        title="Settings action buttons run and are individually addressable",
        contexts=("main-window-browser",),
        precondition="Settings tab, About category.",
        proves="Two rows both titled Copy are told apart by identifier.",
        steps=(
            real("tap", "Settings-category-about", expect="About detail shows."),
            real(
                "tap",
                "Settings-action-version",
                expect="Version copies to the pasteboard.",
            ),
            real(
                "tap",
                "Settings-action-feedback-email",
                expect="Feedback address copies, and it is a different row from "
                "the one above.",
            ),
        ),
    ),
    Unit(
        id="settings.clear-history",
        title="Clearing playback history empties the resume state",
        contexts=("main-window-browser",),
        precondition="At least one recorded viewing position.",
        proves="The destructive settings action reaches persistence.",
        needs=("playback.open",),
        steps=(
            real(
                "tap",
                "Settings-category-storagePrivacy",
                expect="Storage and privacy detail shows.",
            ),
            real(
                "tap",
                "Settings-action-clear-playback-history",
                expect="History is cleared and the cache figure drops to zero.",
            ),
        ),
    ),
    Unit(
        id="emby.connect",
        title="Sign in to an Emby server",
        contexts=("main-window-browser",),
        precondition="Credentials available from the local credentials file.",
        proves="The connection form is fully drivable and the library loads.",
        steps=(
            real(
                "tap",
                "Emby-Navigation-Tab",
                expect="Emby screen is on screen.",
            ),
            real(
                "type",
                "Emby-Connection-Address",
                text="${EMBY_ADDRESS}",
                expect="Address field holds the value.",
            ),
            real(
                "type",
                "Emby-Connection-Username",
                text="${EMBY_USERNAME}",
                expect="Username field holds the value.",
            ),
            real(
                "type",
                "Emby-Connection-Password",
                text="${EMBY_PASSWORD}",
                expect="Password field is filled and never echoed into the log.",
            ),
            real(
                "tap",
                "Emby-Connection-Connect",
                expect="Home view loads with poster rows.",
            ),
        ),
    ),
    Unit(
        id="emby.browse",
        title="Move through the Emby library down to an episode",
        contexts=("main-window-browser",),
        precondition="Signed in to Emby.",
        proves="Search, sort, seasons and the poster wall all navigate.",
        needs=("emby.connect",),
        steps=(
            real(
                "tap",
                "Emby-Sidebar-Toggle",
                expect="Library sidebar hides, then a second tap brings it back. "
                "The toggle sits in the page header of every Emby screen.",
            ),
            real(
                "swipeLeft",
                "Emby-PosterCard-{metadata.id.rawValue}",
                covers=("scroll:emby",),
                expect="Poster row scrolls. Only cards inside the visible band "
                "accept a tap, so scrolling comes first.",
            ),
            real(
                "tap",
                "Emby-PosterCard-{metadata.id.rawValue}",
                expect="Series detail opens.",
            ),
            real(
                "tap",
                "Emby-Detail-Overview-Expand",
                expect="Overview expands.",
            ),
            real(
                "tap",
                "Emby-Season-Picker",
                expect="Season list appears.",
            ),
            real(
                "tap",
                "Emby-Season-{season.metadata.id.rawValue}",
                expect="Episode panel switches to that season.",
            ),
            real(
                "tap",
                "Emby-Library-Sort",
                expect="Sort options appear.",
            ),
            real(
                "tap",
                "Emby-Search-Field",
                expect="Search field takes focus.",
            ),
            real(
                "type",
                "Emby-Search-Field",
                text="the",
                expect="Results narrow to matches.",
            ),
        ),
    ),
    Unit(
        id="emby.play",
        title="Start playback from Emby and record progress on the server",
        contexts=("main-window-browser",),
        precondition="Signed in to Emby.",
        proves="Both play entries work and the server sees the position.",
        needs=("emby.connect",),
        steps=(
            real(
                "tap",
                "Emby-StillCard-{metadata.id.rawValue}",
                expect="Single episode detail opens.",
            ),
            real(
                "tap",
                "Emby-Detail-Version",
                expect="Version list appears when the item has more than one.",
            ),
            real(
                "tap",
                'Emby-Detail-{action == .resume ? "Resume" : "PlayFromBeginning"}',
                expect="Playback starts from the offered position.",
            ),
            evidence(
                "settle",
                "lifecycle=Playing",
                expect="Steady state reached inside the deadline.",
            ),
            real(
                "tap",
                "Emby-Episode-{metadata.id.rawValue}",
                expect="An episode card opens playback directly, without a third "
                "detail level.",
            ),
        ),
    ),
    Unit(
        id="emby.sign-out",
        title="Sign out of Emby",
        contexts=("main-window-browser",),
        precondition="Signed in to Emby.",
        proves="Sign out clears the session and returns to the form.",
        needs=("emby.connect",),
        steps=(
            real(
                "tap",
                "Emby-SignOut",
                expect="Connection form returns and the library is gone.",
            ),
        ),
    ),
    Unit(
        id="playback.open",
        title="Open a library card and reach steady playback",
        contexts=("window",),
        precondition="Fixture in the library.",
        proves="A card tap reaches a decoding, advancing session with real "
        "content on screen.",
        needs=("library.import",),
        steps=(
            real(
                "tap",
                FIXTURE_CARD,
                expect="Playback opens.",
            ),
            evidence(
                "settle",
                "lifecycle=Playing",
                expect="Steady state within the deadline.",
            ),
            evidence(
                "frames",
                "3",
                expect="Three frames at least a second apart, none blank, none "
                "identical, no whole-image colour cast.",
            ),
        ),
    ),
    Unit(
        id="playback.resume-decision",
        title="Reopening a partly watched item offers a resume decision",
        contexts=("main-window-browser",),
        precondition="A recorded position on a long enough item.",
        proves="Both branches of the resume prompt are reachable and honoured.",
        needs=("playback.open",),
        steps=(
            real(
                "tap",
                FIXTURE_CARD,
                expect="Resume prompt appears.",
            ),
            real(
                "tap",
                "PlayerUI-resumeDecision-primary",
                expect="Playback starts at the recorded position.",
            ),
            real(
                "tap",
                "PlayerUI-resumeDecision-secondary",
                expect="Playback starts from the beginning.",
            ),
        ),
    ),
    Unit(
        id="playback.controls-window",
        title="Summon the controls through the gaze-and-pinch pipeline and "
        "use the top bar",
        contexts=("window", "portal",),
        precondition="Steady playback in the window, Device Hub canvas "
        "frontmost for the summon step.",
        proves="The surface collider accepts a real gaze-and-pinch summon "
        "and the top actions respond before auto-hide takes them away.",
        needs=("playback.open",),
        steps=(
            device_hub(
                "pinch",
                "PlayerUI-window-playback-surface",
                entity="EnchronWindowInput.surface",
                probe="spatialTap entity=EnchronWindowInput.surface accepted=true",
                expect="Controls appear and the probe line lands. The surface "
                "is a RealityKit collider behind an input-transparent "
                "accessibility node: a synthetic tap reports success without "
                "reaching it, the channel toggle writes no spatialTap line, "
                "and the harness keeps only the summon: prefix as its "
                "declared injection, so this probe line is evidence only the "
                "Device Hub pipeline produces.",
            ),
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-more",),
                expect="More menu opens. Sent as a sequence because the controls "
                "hide faster than two channel round trips.",
            ),
            real(
                "tap",
                "PlayerUI-InfoBar-button-back",
                expect="Playback closes and the library returns.",
            ),
        ),
    ),
    Unit(
        id="playback.transport",
        title="Play, pause and skip from the transport panel",
        contexts=("window", "portal", "panorama", "docked",),
        precondition="Steady playback with controls on screen.",
        proves="Transport controls move the position and the timebase.",
        needs=("playback.open",),
        steps=(
            real(
                "tap",
                "PlayerPanel-button-play",
                expect="Timebase rate goes to zero and the position stops.",
            ),
            real(
                "tap",
                "PlayerPanel-button-play",
                expect="Timebase rate returns to one and the position advances.",
            ),
            real(
                "tap",
                "PlayerPanel-button-forward",
                expect="Position jumps forward by the skip interval.",
            ),
            real(
                "tap",
                "PlayerPanel-button-rewind",
                expect="Position jumps back by the skip interval.",
            ),
            real(
                "tap",
                "PlayerPanel-progress",
                expect="Progress bar accepts a tap and seeks.",
            ),
            real(
                "doubleTap",
                "PlayerPanel-progress",
                expect="Precision timeline opens. A single tap seeks; the "
                "timeline is a double tap, and it does not exist to be tapped "
                "until that gesture opens it.",
            ),
            real(
                "doubleTap",
                "PlayerPanel-precision-timeline",
                expect="Precision timeline closes, symmetrically.",
            ),
            real(
                "swipeRight",
                "PlayerPanel-progress",
                expect="Progress drag moves the position while playback is paused.",
            ),
            real(
                "tap",
                "PlayerPanel-media-information",
                expect="Media information well expands. The well is its own tap "
                "target, and nothing else opens it.",
            ),
            real(
                "tap",
                "PlayerPanel-media-information-close",
                expect="Media information panel closes.",
            ),
            injected(
                "app",
                "seekNormalized",
                args=("position=0.5",),
                expect="Position lands at half the duration.",
                why="An exact half-duration checkpoint is deterministic setup; "
                "the product drag is relative and cannot target it repeatably.",
                skips="The scrubber hit test, drag gesture and coordinate mapping.",
                blind="A defect limited to those input layers. The preceding real "
                "swipe covers the drag path independently.",
            ),
        ),
    ),
    Unit(
        id="playback.tracks",
        title="Switch audio and subtitle tracks from the more menu",
        contexts=("window", "portal",),
        precondition="Steady playback of a file with several tracks.",
        proves="Track switching keeps the session alive and the picture running.",
        needs=("playback.open",),
        steps=(
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-more", "PlayerUI-menu-audio"),
                expect="Audio track list opens.",
            ),
            real(
                "tap",
                "PlayerUI-menu-audio-{item.id}",
                label="FLAC",
                expect="Selected track changes and playback keeps advancing.",
            ),
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-more", "PlayerUI-menu-subtitles"),
                expect="Subtitle list opens.",
            ),
            real(
                "tap",
                "PlayerUI-menu-subtitles-{item.id}",
                label="English",
                expect="Subtitles appear and playback keeps advancing.",
            ),
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-more", "PlayerUI-menu-speed"),
                expect="Speed list opens.",
            ),
            real(
                "tap",
                "",
                label="1.5x",
                expect="Timebase rate becomes 1.5.",
            ),
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-more", "PlayerUI-menu-episodes"),
                expect="Episode list opens for a series item.",
            ),
            evidence(
                "app",
                "listMenuItems",
                expect="Selected track reads back as selected.",
            ),
        ),
    ),
    Unit(
        id="playback.format-editor",
        title="Change projection and stereo layout through the format editor",
        contexts=("window", "portal",),
        precondition="Steady playback in the window.",
        proves="A format change reaches the renderer and the presentation follows.",
        needs=("playback.open",),
        steps=(
            real(
                "tap",
                "PlayerUI-TopAction-videoFormat",
                expect="Format editor opens.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-{title}-{label(option)}",
                label="180°",
                expect="Projection selection changes.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-CustomAngle",
                expect="Custom angle entry appears.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-HDRFallback",
                expect="Fallback transfer choice changes.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-automatic",
                expect="Editor returns to the detected format.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-apply",
                expect="Presentation becomes portal with the chosen projection.",
            ),
            real(
                "tap",
                "PlayerUI-TopAction-videoFormat",
                expect="Editor opens again.",
            ),
            real(
                "tap",
                "PlayerUI-VideoFormat-cancel",
                expect="Editor closes with the format unchanged.",
            ),
        ),
    ),
    Unit(
        id="playback.dock",
        title="Dock the player into an environment",
        contexts=("window",),
        precondition="Steady flat playback in the window.",
        proves="Docking attaches the surface and the renderer keeps producing.",
        needs=("playback.open",),
        steps=(
            real(
                "tapSequence",
                "",
                identifiers=("PlayerUI-TopAction-dock", "PlayerUI-DockMenu-skybox"),
                expect="Docked presentation is requested.",
            ),
            evidence(
                "settle",
                "attached=docked",
                expect="All nine spatial facts hold inside the settlement "
                "deadline.",
            ),
            real(
                "tap",
                "PlayerUI-DockMenu-{$0.rawValue}",
                label="Mount Hood",
                expect="Environment changes without a new session.",
            ),
        ),
    ),
    Unit(
        id="playback.panorama",
        title="Enter panorama and come back",
        contexts=("portal",),
        precondition="Portal presentation reached through the format editor.",
        proves="Immersive entry settles and the window is not left resident.",
        needs=("playback.format-editor",),
        steps=(
            real(
                "tap",
                "PlayerUI-TopAction-resumePanorama",
                expect="Immersive space opens and settles.",
            ),
            evidence(
                "assert",
                "negative:immersive-resident-window",
                context="panorama",
                covers=("negative:immersive-resident-window",),
                expect="The main window is not in the hierarchy while immersive.",
            ),
            injected(
                "app",
                "toggleControls",
                context="panorama",
                expect="Controls appear over the immersive scene.",
                **CONTROLS_ARE_SPATIAL,
            ),
            real(
                "tap",
                "PlayerPanel-menu-more",
                context="panorama",
                expect="The panorama panel opens its more menu.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-audio",
                context="panorama",
                expect="Audio list opens over the immersive scene.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-{category}-{item.id}",
                context="panorama",
                label="FLAC",
                expect="Track changes without leaving panorama.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-subtitles",
                context="panorama",
                expect="Subtitle list opens over the immersive scene.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-speed",
                context="panorama",
                expect="Speed list opens over the immersive scene.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-episodes",
                context="panorama",
                expect="Episode list opens over the immersive scene, or the "
                "control is absent for single-file media.",
            ),
            real(
                "tap",
                "PlayerPanel-button-exit-spatial",
                context="panorama",
                expect="Immersive space closes and the window returns.",
            ),
        ),
    ),
    Unit(
        id="docked.panel",
        title="Drive the whole docked panel",
        contexts=("docked",),
        precondition="Docked presentation settled.",
        proves="Every docked control responds once the panel is on screen.",
        needs=("playback.dock",),
        steps=(
            injected(
                "app",
                "toggleControls",
                expect="Docked panel appears.",
                **CONTROLS_ARE_SPATIAL,
            ),
            real(
                "tap",
                "PlayerPanel-button-settings",
                expect="Placement controls appear.",
            ),
            real(
                "tap",
                "PlayerPanel-{identifier}-slider",
                label="Screen Size",
                expect="Screen size changes. The three sliders are screen size, "
                "distance and elevation.",
            ),
            real(
                "tap",
                "PlayerPanel-DockedPlacement-reset",
                expect="Placement returns to its default.",
            ),
            injected(
                "app",
                "setDockedPlacement",
                args=("screenSize=0.8",),
                expect="Placement takes an exact value for the assertion below.",
                why="The sliders are continuous and synthetic input cannot land "
                "on an exact value.",
                skips="The slider drag.",
                blind="Any defect in the slider gesture. The tap above proves the "
                "slider is reachable.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-more",
                expect="Docked more menu opens.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-audio",
                expect="Audio list opens in the docked panel.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-{category}-{item.id}",
                label="FLAC",
                expect="Track changes from the docked panel.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-subtitles",
                expect="Subtitle list opens.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-speed",
                expect="Speed list opens.",
            ),
            real(
                "tap",
                "PlayerPanel-menu-episodes",
                expect="Episode list opens.",
            ),
            evidence(
                "assert",
                "negative:immersive-resident-window",
                covers=("negative:immersive-resident-window",),
                expect="The main window is not resident behind the docked scene.",
            ),
        ),
    ),
    Unit(
        id="environment.card",
        title="Open the environment card and change the scene",
        contexts=("window", "docked",),
        precondition="Playback on screen.",
        proves="The environment card is reachable and does not block the "
        "controls behind it.",
        steps=(
            real(
                "tap",
                "EnvironmentCard-card",
                expect="Environment card opens.",
            ),
            real(
                "swipeLeft",
                "EnvironmentCard-carousel",
                expect="Carousel scrolls through environments.",
            ),
            real(
                "tap",
                "EnvironmentCard-button-environment-{environment.environment.rawValue}",
                label="Mount Hood",
                expect="Environment changes.",
            ),
            real(
                "tap",
                "EnvironmentCard-effect-{environment.environment.rawValue}",
                label="Mount Hood",
                expect="Effect toggles.",
            ),
            injected(
                "app",
                "openEnvironmentCard",
                expect="Environment volume opens.",
                why="The environment volume is a separate scene whose open "
                "gesture lives outside the app window.",
                skips="The system gesture that opens the volume.",
                blind="Any defect in that gesture. What the volume does once open "
                "is checked by the real taps above.",
                covers=("environmentVolume:open-interact-close",),
            ),
            injected(
                "app",
                "dismissEnvironmentCard",
                expect="Environment volume closes.",
                why="Closing the volume is the same separate scene.",
                skips="The system gesture that closes the volume.",
                blind="Any defect in that gesture.",
            ),
        ),
    ),
    Unit(
        id="issues.playback-surfaces",
        title="Every playback issue surface can be read and dismissed",
        contexts=("window", "portal",),
        precondition="Steady playback.",
        proves="The issue policy table renders and its actions work.",
        needs=("playback.open",),
        steps=(
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=mediaOpeningFailed",),
                expect="Load failure surface appears with two actions.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-loadFailure-primary",
                expect="Primary action retries.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=mediaOpeningFailed",),
                expect="Load failure surface appears again.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-loadFailure-secondary",
                expect="Secondary action leaves playback.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=playbackFailed",),
                expect="Playback issue surface appears.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-playbackIssue-confirm",
                expect="Surface closes.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=capabilityUnavailable",),
                expect="Unmet capability surface appears.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-unmetCapability-dismiss",
                expect="Surface closes.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=presentationConversionFailed",),
                expect="Conversion failure surface appears.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-presentation-conversion-dismiss",
                context="main-window-browser",
                expect="Surface closes. Conversion failure is raised by the "
                "browser window, so the dismissal is a browser hit test.",
            ),
        ),
    ),
    Unit(
        id="issues.spatial-surfaces",
        title="Spatial failure surfaces can be read and dismissed",
        contexts=("panorama", "docked",),
        precondition="Immersive presentation.",
        proves="The immersive failure surface offers both actions.",
        needs=("playback.panorama",),
        steps=(
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=surfaceAttachmentFailed",),
                expect="Spatial failure surface appears.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-spatialFailure-primary",
                expect="Primary action retries the attachment.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=surfaceAttachmentFailed",),
                expect="Spatial failure surface appears again.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-spatialFailure-secondary",
                expect="Secondary action leaves the immersive scene.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=playbackFailed",),
                expect="Playback issue surface appears over the immersive scene.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-playbackIssue-confirm",
                expect="Surface closes. The immersive host hit-tests it "
                "independently of the window host.",
            ),
            injected(
                "app",
                "showPlaybackIssue",
                args=("category=capabilityUnavailable",),
                expect="Unmet capability surface appears over the immersive scene.",
                **FAULT_HAS_NO_PRODUCT_PATH,
            ),
            real(
                "tap",
                "PlayerUI-unmetCapability-dismiss",
                expect="Surface closes.",
            ),
        ),
    ),
    Unit(
        id="window.geometry",
        title="The portal window takes the size the product asks for",
        contexts=("portal",),
        precondition="Portal presentation.",
        proves="Window resize reaches the scene and the renderer follows.",
        needs=("playback.format-editor",),
        steps=(
            injected(
                "app",
                "setWindowSize",
                args=("width=1280", "height=720"),
                expect="Portal window reports the requested size.",
                why="Window resize is a system chrome drag with no in-app control.",
                skips="The system window resize handle.",
                blind="Any defect in the resize handle itself.",
            ),
        ),
    ),
    Unit(
        id="playback.exit-spatial",
        title="Leave the spatial presentation and return to the library",
        contexts=("docked", "panorama",),
        precondition="Docked or panorama presentation.",
        proves="Exit tears down the immersive scene and restores the window.",
        needs=("playback.dock",),
        steps=(
            real(
                "tap",
                "PlayerPanel-button-exit-spatial",
                expect="Window presentation returns with playback intact.",
            ),
            evidence(
                "app",
                "exitSpatial",
                expect="Spatial scene is confirmed torn down.",
            ),
        ),
    ),
)

REFUSED_BECAUSE_DEVICE_HUB_OWNS_THE_SUMMON = (
    "Deliberately unused here. The controls are summoned by real gaze and "
    "pinch on the surface collider in this presentation, the channel toggle "
    "survives in the synthetic harness only as the summon: step prefix, and "
    "exempting it keeps that injection from standing in for Device Hub "
    "evidence."
)
SUPERSEDED_BY_REAL_MENU_TAPS = (
    "Superseded. Measured on device 2026-08-20: the menu host is hittable, the "
    "items render in the hierarchy, and tapping one by label changes the value. "
    "The verb stays in the app only until every menu host has been driven for "
    "real, then it is deleted."
)

# A cell lands here when no unit drives it and the reason is stated. Two reasons
# are legitimate. The platform refuses, or we refuse: an injection that would
# skip a path we can actually walk does not earn its place.
EXEMPTIONS: dict[tuple[str, str], str] = {
    **{
        (context, "command:toggleControls"): REFUSED_BECAUSE_DEVICE_HUB_OWNS_THE_SUMMON
        for context in ("window", "portal")
    },
    **{
        (context, "command:selectMenuItem"): SUPERSEDED_BY_REAL_MENU_TAPS
        for context in ("main-window-browser", "window", "portal", "panorama", "docked")
    },
    **{
        (context, "command:listMenuItems"): (
            "Read-only. It reports which track is selected and asserts nothing "
            "about reachability, so it is evidence rather than an operation."
        )
        for context in ("main-window-browser", "window", "portal", "panorama", "docked")
    },
}


def inventory() -> dict[str, object]:
    return json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))


def matrix_cells() -> list[tuple[str, str]]:
    """The axes come from the source-derived inventory, never from the physical
    baseline. A baseline lags every product change by one device run, so reading
    it would let a newly added operation escape coverage until someone happened
    to re-accept the matrix."""
    return [
        (context, operation["id"])
        for operation in inventory()["operations"]
        for context in operation["proofContexts"]
    ]


def identifier_operations() -> list[tuple[re.Pattern[str], str]]:
    """Templates ordered most specific first.

    `Emby-Detail-Overview-Expand` matches both its own template and the wildcard
    `Emby-Detail-{...}`. Literal characters outside the placeholders decide, so
    the exact template always beats the wildcard that happens to swallow it.
    """
    entries = [
        (
            len(re.sub(r"\{.*?\}", "", operation["identifierTemplate"])),
            template_pattern(operation["identifierTemplate"]),
            operation["id"],
        )
        for operation in inventory()["operations"]
        if operation["id"].startswith("accessibility:")
    ]
    entries.sort(key=lambda entry: -entry[0])
    return [(pattern, identifier) for _, pattern, identifier in entries]


def match_operation(target: str, patterns: list[tuple[re.Pattern[str], str]]) -> str | None:
    hits = [operation for pattern, operation in patterns if pattern.fullmatch(target)]
    return hits[0] if hits else None


def entity_input_operations() -> dict[str, dict[str, object]]:
    return {
        operation["id"]: operation
        for operation in inventory()["operations"]
        if operation["proofContextDerivation"].get("host") in ENTITY_INPUT_HOSTS
    }


def probe_matches_contract(entity: str, probe: str) -> bool:
    return (
        probe.startswith("spatialTap ")
        and f"entity={entity}" in probe
        and "accepted=true" in probe
    )


def entity_input_complaints(
    step: Step,
    patterns: list[tuple[re.Pattern[str], str]],
    entity_operations: dict[str, dict[str, object]],
) -> list[str]:
    complaints: list[str] = []
    matched: list[str] = []
    for candidate in step.targets():
        operation = match_operation(candidate, patterns)
        if operation:
            matched.append(operation)
    matched_entity = [
        operation for operation in matched if operation in entity_operations
    ]
    if step.drive != DEVICE_HUB:
        if step.entity or step.probe:
            complaints.append(
                "declares entity or probe evidence, which only a device-hub "
                "step may carry"
            )
        if step.verb == "pinch":
            complaints.append(
                "uses the pinch verb outside the device-hub pipeline"
            )
        if matched_entity and step.drive != EVIDENCE:
            complaints.append(
                f"{', '.join(matched_entity)} is a RealityKit input target "
                "(2026-08-25 R5/Q11): synthetic XCUI events never reach the "
                "collider and still report success against its "
                "input-transparent accessibility node, so only a device-hub "
                "step can drive it"
            )
        return complaints
    if step.verb != "pinch":
        complaints.append(
            "device-hub steps land as gaze plus pinch; use the pinch verb"
        )
    if not matched or len(matched_entity) != len(matched):
        complaints.append(
            "device-hub steps may target only RealityKit input targets; a "
            "synthetic-reachable control stays on a real step so the "
            "device-hub drive keeps meaning evidence only that pipeline "
            "produces"
        )
    if not step.entity:
        complaints.append("names no collider entity")
    elif not any(
        step.entity in (REPOSITORY_ROOT / source["path"]).read_text(encoding="utf-8")
        for operation in matched_entity
        for source in entity_operations[operation]["proofContextDerivation"]["sources"]
    ):
        complaints.append(
            f"entity {step.entity!r} appears in none of the target "
            "operation's derivation sources"
        )
    if not probe_matches_contract(step.entity, step.probe):
        complaints.append(
            "probe must be the app-side spatialTap line "
            "(spatialTap entity=<entity> ... accepted=true); the command "
            "channel writes no spatialTap lines, so nothing synthetic can "
            "produce this evidence"
        )
    return complaints


def derived_claims(
    step: Step,
    unit_contexts: tuple[str, ...],
    patterns: list[tuple[re.Pattern[str], str]],
) -> list[tuple[str, str]]:
    """The cells a step covers by construction rather than by declaration.

    Touching a control with a drive mode that exercises it is the proof; saying
    so a second time in `covers` only creates a second thing to keep in sync.
    Setup and evidence steps derive nothing, because reaching a screen and
    reading it back are not the operation.
    """
    if step.drive not in (REAL, INJECTED, WEARER, DEVICE_HUB):
        return []
    operations: list[str] = []
    for candidate in step.targets():
        operation = match_operation(candidate, patterns)
        if operation:
            operations.append(operation)
    if step.verb == "app" and step.target:
        operations.append(f"command:{step.target}")
    return [
        (context, operation)
        for operation in operations
        for context in step.contexts(unit_contexts)
    ]


def template_pattern(name: str) -> re.Pattern[str]:
    escaped = re.escape(name)
    return re.compile(re.sub(r"\\\{.*?\\\}", ".+", escaped))


def step_supports(step: Step, operation: str) -> str | None:
    """Returns None when the step really does exercise the operation, or the
    reason the claim does not hold."""
    kind, _, name = operation.partition(":")
    if kind == "accessibility":
        pattern = template_pattern(name)
        for candidate in step.targets():
            if pattern.fullmatch(candidate):
                return None
        return (
            f"claims {operation} but targets "
            f"{step.targets() or ('nothing',)!r}"
        )
    if kind == "command":
        if step.verb == "app" and step.target == name:
            return None
        return f"claims {operation} but is not an app-command for {name}"
    if kind == "menu":
        if step.drive == REAL and step.verb in ("tap", "tapSequence"):
            return None
        if step.drive == INJECTED and step.target == "selectMenuItem":
            return None
        return (
            f"claims {operation} but neither taps the host for real nor declares "
            "selectMenuItem as an injection"
        )
    if kind == "scroll":
        if step.verb.startswith("swipe") and step.targets():
            return None
        return (
            f"claims {operation} but is not a swipe with an identifier. A bare "
            "swipe degrades to the Application element and kills the session."
        )
    if kind == "environmentVolume":
        if step.verb == "app" or step.verb == "tap":
            return None
        return f"claims {operation} with an unrelated verb"
    if kind == "negative":
        if step.verb == "assert":
            return None
        return f"claims {operation} but is not an assertion"
    return f"unknown operation kind {kind!r}"


def check() -> int:
    failures: list[str] = []
    cells = matrix_cells()
    known = set(cells)
    patterns = identifier_operations()
    commands = app_commands()
    entity_operations = entity_input_operations()
    hosts = {
        operation["proofContextDerivation"].get("host")
        for operation in inventory()["operations"]
    }
    for host in sorted(ENTITY_INPUT_HOSTS - hosts):
        failures.append(
            f"entity-input host {host!r} is no longer in the inventory; the "
            "derivation moved and this set is stale"
        )
    seen: set[tuple[str, str]] = set()
    unit_ids = set()

    for unit in UNITS:
        if unit.id in unit_ids:
            failures.append(f"{unit.id}: duplicate unit id")
        unit_ids.add(unit.id)
        for need in unit.needs:
            if need not in {other.id for other in UNITS}:
                failures.append(f"{unit.id}: needs unknown unit {need!r}")
        if not unit.contexts:
            failures.append(f"{unit.id}: names no context")
        for context in unit.contexts:
            if context not in {c for c, _ in cells}:
                failures.append(f"{unit.id}: unknown context {context!r}")
        for position, step in enumerate(unit.steps, start=1):
            where = f"{unit.id} step {position}"
            if step.verb not in VERBS:
                failures.append(f"{where}: unknown verb {step.verb!r}")
            if step.verb == "app" and step.target not in commands:
                failures.append(
                    f"{where}: app command {step.target!r} is not in "
                    f"{COMMAND_CHANNEL_PATH.relative_to(REPOSITORY_ROOT)}"
                )
            if step.drive not in DRIVES:
                failures.append(f"{where}: unknown drive {step.drive!r}")
            if step.drive == INJECTED:
                if step.injection is None:
                    failures.append(f"{where}: injected without a declaration")
                else:
                    for name in ("why", "skips", "blind"):
                        if not getattr(step.injection, name).strip():
                            failures.append(f"{where}: injection {name} is empty")
            if step.drive != INJECTED and step.injection is not None:
                failures.append(f"{where}: declares an injection but is not injected")
            for complaint in entity_input_complaints(
                step, patterns, entity_operations
            ):
                failures.append(f"{where}: {complaint}")
            if not step.expect.strip():
                failures.append(f"{where}: no expectation")
            derived = derived_claims(step, unit.contexts, patterns)
            for entry in step.covers:
                if any(operation == entry for _, operation in derived):
                    failures.append(
                        f"{where}: covers {entry}, which the step's own target "
                        "already says. Delete the declaration; a second copy can "
                        "only ever drift from the first."
                    )
            for context, operation in step.claims(unit.contexts):
                complaint = step_supports(step, operation)
                if complaint:
                    failures.append(f"{where}: {complaint}")
                    continue
                if (context, operation) not in known:
                    failures.append(
                        f"{where}: {context} | {operation} is not in the "
                        "reachability matrix"
                    )
                    continue
                seen.add((context, operation))
            seen.update(cell for cell in derived if cell in known)

    for cell in sorted(known - seen - set(EXEMPTIONS)):
        failures.append(f"uncovered: {cell[0]} | {cell[1]}")
    for cell in sorted(set(EXEMPTIONS) - known):
        failures.append(f"exemption for a cell the matrix no longer has: {cell}")
    for cell in sorted(set(EXEMPTIONS) & seen):
        failures.append(
            f"exemption for a cell that is covered anyway: {cell[0]} | {cell[1]}"
        )
    if not LEDGER_PATH.is_file():
        failures.append(
            f"missing {LEDGER_PATH.relative_to(REPOSITORY_ROOT)}; run "
            "Scripts/verification/journey_units.py ledger"
        )
    elif LEDGER_PATH.read_text(encoding="utf-8") != ledger_text():
        failures.append(
            "the committed coverage ledger no longer matches the units; run "
            "Scripts/verification/journey_units.py ledger"
        )
    if not REFERENCE_PATH.is_file():
        failures.append(
            f"missing {REFERENCE_PATH.relative_to(REPOSITORY_ROOT)}; run "
            "Scripts/verification/journey_units.py reference"
        )
    elif REFERENCE_PATH.read_text(encoding="utf-8") != reference_text():
        failures.append(
            "the skill's operation-unit reference no longer matches the units; run "
            "Scripts/verification/journey_units.py reference"
        )

    print(f"units {len(UNITS)}, steps {sum(len(u.steps) for u in UNITS)}")
    print(f"matrix cells {len(known)}, covered {len(seen)}, exempt {len(EXEMPTIONS)}")
    drives: dict[str, int] = {}
    for unit in UNITS:
        for step in unit.steps:
            drives[step.drive] = drives.get(step.drive, 0) + 1
    for drive in sorted(drives):
        print(f"  {drive}: {drives[drive]}")

    if failures:
        print()
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        print(f"\n{len(failures)} problems.", file=sys.stderr)
        return 1
    return 0


def covered_by(patterns: list[tuple[re.Pattern[str], str]]) -> dict[tuple[str, str], dict[str, object]]:
    """The step that proves each cell, first one wins."""
    assignment: dict[tuple[str, str], dict[str, object]] = {}
    for unit in UNITS:
        for position, step in enumerate(unit.steps, start=1):
            cells = [
                cell
                for cell in step.claims(unit.contexts)
                if step_supports(step, cell[1]) is None
            ]
            cells.extend(derived_claims(step, unit.contexts, patterns))
            entry: dict[str, object] = {
                "unit": unit.id,
                "step": position,
                "drive": step.drive,
                "expect": step.expect,
            }
            if step.drive == DEVICE_HUB:
                entry["probe"] = step.probe
            for cell in cells:
                assignment.setdefault(cell, dict(entry))
    return assignment


def ledger_text() -> str:
    assignment = covered_by(identifier_operations())
    entries = []
    for context, operation in matrix_cells():
        entry: dict[str, object] = {"context": context, "operation": operation}
        found = assignment.get((context, operation))
        if found:
            entry.update(found)
        elif (context, operation) in EXEMPTIONS:
            entry["status"] = "exempt"
            entry["reason"] = EXEMPTIONS[(context, operation)]
        else:
            entry["status"] = "unassigned"
        entries.append(entry)
    entries.sort(key=lambda entry: (entry["context"], entry["operation"]))
    return (
        json.dumps(
            {
                "schemaVersion": 3,
                "generatedFrom": "Scripts/verification/journey_units.py",
                "cells": entries,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )


def write_ledger() -> int:
    text = ledger_text()
    LEDGER_PATH.write_text(text, encoding="utf-8")
    count = len(json.loads(text)["cells"])
    print(f"wrote {LEDGER_PATH.relative_to(REPOSITORY_ROOT)} with {count} cells")
    return 0


def show() -> int:
    for unit in UNITS:
        injections = sum(1 for step in unit.steps if step.drive == INJECTED)
        handoffs = sum(1 for step in unit.steps if step.drive == WEARER)
        marks = []
        if injections:
            marks.append(f"{injections} injected")
        if handoffs:
            marks.append(f"{handoffs} wearer")
        suffix = f"  [{', '.join(marks)}]" if marks else ""
        print(f"{unit.id}  ({'+'.join(unit.contexts)}, {len(unit.steps)} steps){suffix}")
        print(f"    {unit.title}")
        print(f"    proves: {unit.proves}")
        if unit.needs:
            print(f"    needs: {', '.join(unit.needs)}")
    return 0


def step_line(step: Step) -> str:
    parts = [f"`{step.drive}`", step.verb]
    if step.target:
        parts.append(f"`{step.target}`")
    if step.label:
        parts.append(f"label {step.label}")
    if step.index is not None:
        parts.append(f"index {step.index}")
    if step.text is not None:
        parts.append(f"text {step.text}")
    if step.args:
        parts.append(" ".join(step.args))
    if step.identifiers:
        parts.append("across " + ", ".join(f"`{name}`" for name in step.identifiers))
    if step.context:
        parts.append(f"in {step.context}")
    return " ".join(parts)


def reference_text() -> str:
    lines = [
        "# Operation units",
        "",
        "Generated by `Scripts/verification/journey_units.py reference`. Every unit "
        "below ends in a verdict you read before choosing the next one. Run them in "
        "the order their `needs` imply, not top to bottom.",
        "",
        f"{len(UNITS)} units, {sum(len(unit.steps) for unit in UNITS)} steps, "
        f"{len(matrix_cells())} reachability cells.",
        "",
        "`real` drives the product through its own hit testing. `injected` reaches "
        "past some of that path and says what it skips, so a pass there is worth "
        "less than a pass beside it. `setup` and `evidence` prove nothing on their "
        "own. `wearer` needs the human in the headset. `device-hub` drives a "
        "RealityKit input target through the system gaze-and-pinch pipeline "
        "(Device Hub canvas: hover is gaze, click is pinch); its proof is the "
        "app-side spatialTap probe line, which neither a synthetic tap nor the "
        "command channel can produce.",
        "",
    ]
    for unit in UNITS:
        lines.append(f"## {unit.id}")
        lines.append("")
        lines.append(unit.title + ".")
        lines.append("")
        lines.append(f"- presentation: {', '.join(unit.contexts)}")
        lines.append(f"- precondition: {unit.precondition}")
        lines.append(f"- proves: {unit.proves}")
        if unit.needs:
            lines.append(f"- needs: {', '.join(unit.needs)}")
        lines.append("")
        for position, step in enumerate(unit.steps, start=1):
            lines.append(f"{position}. {step_line(step)}")
            lines.append(f"   - expect: {step.expect}")
            if step.injection:
                lines.append(f"   - why injected: {step.injection.why}")
                lines.append(f"   - skips: {step.injection.skips}")
                lines.append(f"   - blind to: {step.injection.blind}")
            if step.drive == DEVICE_HUB:
                lines.append(f"   - entity: `{step.entity}`")
                lines.append(f"   - probe: `{step.probe}`")
        lines.append("")
    lines.append("## Uncovered by design")
    lines.append("")
    for (context, operation), reason in sorted(EXEMPTIONS.items()):
        lines.append(f"- `{context}` | `{operation}`. {reason}")
    lines.append("")
    return "\n".join(lines)


def write_reference() -> int:
    REFERENCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    REFERENCE_PATH.write_text(reference_text(), encoding="utf-8")
    print(f"wrote {REFERENCE_PATH.relative_to(REPOSITORY_ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        nargs="?",
        default="check",
        choices=("check", "list", "ledger", "reference"),
    )
    arguments = parser.parse_args()
    if arguments.action == "check":
        return check()
    if arguments.action == "list":
        return show()
    if arguments.action == "reference":
        return write_reference()
    return write_ledger()


if __name__ == "__main__":
    sys.exit(main())
