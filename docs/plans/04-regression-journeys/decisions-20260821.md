# Regression suite, decisions of 2026-08-21

## What the suite is now

The regression suite is a set of operation units in
`Scripts/verification/journey_units.py`. A unit is the smallest chunk of device
driving that ends in a verdict, usually several taps and a few seconds. The
agent reads that verdict and picks the next unit, which is what lets a
regression run stay current-driven rather than becoming a script whose result
arrives an hour later as one bit.

38 units, 215 steps, 211 reachability cells, 199 covered by a step and 12
carrying a written exemption. The generated reference the skill reads is
`.agents/skills/vp-e2e/references/operation-units.md`.

## Decisions

**Coverage is derived from what a step drives, not declared beside it.** A step
that taps an identifier covers the inventory operation that identifier belongs
to, in the presentation the step runs in. Declaring it again is now rejected.
The old model let a claim contradict the step that supposedly made it, and one
entry did exactly that. Removing 119 declarations changed no cell.

**Only what a target string cannot express stays declared.** A menu opening, a
scroll, an environment volume round trip, an absence asserted.

**Setup and evidence steps cover nothing.** Reaching a screen and reading it
back are not the operation. Without this, bring-up would inflate coverage.

**The axes come from the source-derived inventory, not the physical baseline.**
A baseline lags the product by one device run. Reading it let a newly added
operation escape coverage until someone re-accepted the matrix.

**An identifier is an operation when an interactive construct sits on its own
modifier chain.** That is a fact about the element rather than about what is
near it in the file. Proximity alone only asks for a decision and is recorded
in `REVIEWED_OBSERVATIONS`. This promoted `PlayerUI-window-playback-surface`,
`Emby-Sidebar-Toggle` and `PlayerPanel-media-information`.

**A script that runs every unit was not built.** It is the aggregated run the
current-driven principle refuses. The controller already sends one command per
invocation, which is the right granularity.

## What the device run found

`resetState` reported only what it deleted, so `library.reset`'s verdict, which
every later unit depends on, could not be read from its own response. It and
`listLibrary` now report the library they leave behind.

SwiftUI keeps `.accessibilityIdentifier` only where a system container promotes
the content to a first-class action. Confirmed in both directions on the
device: an alert's Button keeps its identifier while the TextField beside it
loses one the source declares, and a Menu's buttons keep theirs while an inline
Picker's rows lose identifiers added specifically to test it. Those elements are
still drivable by label, and the sort menu really does change selection that
way. `textInputElement` now falls back to label and then placeholder.

The Cancel button in both library alerts had no identifier at all. A control
with no identifier is absent from the inventory, so no cell demands coverage for
it and no report can go red over it.

`settings.menus` asked the app to `relaunch`, which is a controller verb rather
than an app command. The check now reads `TestCommandChannel.swift` and refuses
any `app` step naming a verb that is not a case in it.

## Verified on the device

`session.open`, `library.reset`, `library.import`, `library.new-folder`, the
sort control of `files.chrome`, and `playback.open`. Playback carries pixel
evidence: three distinct 1920x1080 frames showing correct saturated colour bars,
the gradient sweep and the frame counter, with `formatReady=true`,
`presentation=window` and `videoVisible=true` in the control plane.

## Open

**The gate is red on `reachability-inventory`, and that blocks the merge.** The
physical baseline holds 202 cells while the inventory now needs 213, because the
inventory gained operations today: `PlayerUI-window-playback-surface`,
`Emby-Sidebar-Toggle`, `PlayerPanel-media-information`, `Settings-action-{id}`,
`Settings-menu-{id}`, and the two alert cancel buttons. Every one of those is a
real control that was previously outside the system.

Clearing it needs `reachability_matrix.py --accept-baseline`, which only writes a
baseline when the run reaches `status == "complete"` with no regressions. That is
a full physical pass over all 213 cells, not a patch for the eleven new ones, and
it is a multi-hour device run. Do not hand-edit the baseline: it is device
evidence, and three of the new cells were driven for real on 2026-08-21 while the
rest have never been measured.

The runtime hierarchy contains interactive elements with no identifier, and
nothing currently notices. A static scan cannot answer this because DesignSystem
components receive their identifier as a parameter. The measurement that works
is the hierarchy itself, filtered to elements whose ancestors are also
unidentified. That filter is the next structural guard.

The picker-opening steps of `library.import`, `library.import-entries` and the
remaining wearer handoffs need the human in the headset. Everything the
controller can reach around them has been driven.
