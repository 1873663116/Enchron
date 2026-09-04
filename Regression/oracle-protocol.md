# Oracle evaluation protocol

This file is the implementation locator for every Regression Catalog v1 Oracle. Each Oracle contract declares one accepted typed evidence pair, and each obligation supplies one reviewed rubric. The current Catalog routes every runtime judgment to the pinned Agent provider; no human judgment occurs during a run.

## Validate evidence before judgment

Read the archive manifest and every referenced artifact. Each artifact must contain non-empty bytes, a known producer `callId`, the current build identity, one Scenario attempt identity, one concrete lane, and a capture time within that attempt. Reject evidence from another attempt or lane. Reject an archive when any listed static case lacks its required source calls.

Invalid, incomplete, stale, or mixed-provenance evidence yields `Indeterminate`. Valid evidence that establishes every criterion and matches no negative control yields `Satisfied`. Valid evidence that falsifies a criterion or matches a negative control yields `Violated`.

## Read a rubric at three tiers

A field assertion a rubric states in the shape `field value`, `field=value` or `field true|false` compiles to a deterministic predicate and is read against the call's own structured output. `Scripts/regression/rubric_compiler.py` compiles them; `Scripts/rules/check_rubric_predicate_coverage.py` reports, per criterion, whether one exists, and refuses a drop below the recorded baseline. A criterion that yields a predicate is only partly mechanised: the predicate covers the assertion it names and nothing else.

A pixel-level failure signature is decided by a fixed heuristic rather than by judgment. `Scripts/regression/tools/pixel_heuristics.py` reads a capture that is one pixel on a side, a frame carrying no rendered content, and a pair of frames that did not change. Each returns an identifier from the registry in `Scripts/regression/tools/signatures.py`; a verdict names one of those identifiers or none.

An Agent reads what neither tier decided, and only after the anomaly bundle. The bundle is its whole input: the frames around the call that deviated, the montage those frames tile into, the structured fields that call produced, and the signatures its frames matched. An Agent Oracle reads the complete typed Operation observation, its obligation and case identity, producer Operation and arguments, and every content-bound attachment. Structured Oracle variants restrict evidence to named fields, ordered events, accessibility nodes, timestamps, and byte-level artifact properties. Visual and audio variants may additionally inspect the accepted media. Read the relevant file under `.agents/skills/vp-e2e/features/` to interpret the product state, but use only the bound rubric to decide the obligation. Return the evidence references and a separate result for every criterion and negative control so another reviewer can reproduce the verdict.

The compiler, capability gateway, provenance checks, evidence schema validation and SuccessExpression are deterministic. A rubric written as natural-language criteria is not called deterministic unless an exact field predicate implementation exists. Where one does, the criterion is read deterministically; where none does, the criterion is read by an Agent and the coverage report names it.

One valid evaluation produces the obligation result. Repeated evaluation may resolve `Indeterminate`, but repeated results are not votes and cannot weaken a criterion.

## Evaluate static case conjunction

Case keys in Scenario call IDs are fixed catalog data. They do not create runtime sub-Scenarios. The Oracle checks every listed case in the same Scenario attempt and lane, then returns one obligation result. The Oracle cannot return `Satisfied` when any case is absent, comes from another attempt or lane, or fails a required criterion.

## Keep judgment separate from execution

The Oracle cannot run product actions, change applicability facts, edit the rubric, or supply missing evidence. It decides only the current obligation. The Scenario success expression is evaluated from obligation results after every Oracle result passes provenance checks.
