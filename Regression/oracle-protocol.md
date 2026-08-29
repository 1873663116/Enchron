# Oracle evaluation protocol

This file is the implementation locator for every Regression Catalog v1 Oracle. Each Oracle contract declares one accepted typed evidence pair, and each obligation supplies one reviewed rubric. The current Catalog routes every runtime judgment to the pinned Agent provider; no human judgment occurs during a run.

## Validate evidence before judgment

Read the archive manifest and every referenced artifact. Each artifact must contain non-empty bytes, a known producer `callId`, the current build identity, one Scenario attempt identity, one concrete lane, and a capture time within that attempt. Reject evidence from another attempt or lane. Reject an archive when any listed static case lacks its required source calls.

Invalid, incomplete, stale, or mixed-provenance evidence yields `Indeterminate`. Valid evidence that establishes every criterion and matches no negative control yields `Satisfied`. Valid evidence that falsifies a criterion or matches a negative control yields `Violated`.

## Run Agent Oracles

An Agent Oracle reads the complete typed Operation observation, its obligation and case identity, producer Operation and arguments, and every content-bound attachment. Structured Oracle variants restrict evidence to named fields, ordered events, accessibility nodes, timestamps, and byte-level artifact properties. Visual and audio variants may additionally inspect the accepted media. Read the relevant file under `.agents/skills/vp-e2e/features/` to interpret the product state, but use only the bound rubric to decide the obligation. Return the evidence references and a separate result for every criterion and negative control so another reviewer can reproduce the verdict.

The compiler, capability gateway, provenance checks, evidence schema validation and SuccessExpression are deterministic. A rubric written as natural-language criteria is not called deterministic unless an exact field predicate implementation exists; the current Catalog has no such runtime Oracle.

One valid evaluation produces the obligation result. Repeated evaluation may resolve `Indeterminate`, but repeated results are not votes and cannot weaken a criterion.

## Evaluate static case conjunction

Case keys in Scenario call IDs are fixed catalog data. They do not create runtime sub-Scenarios. The Oracle checks every listed case in the same Scenario attempt and lane, then returns one obligation result. The Oracle cannot return `Satisfied` when any case is absent, comes from another attempt or lane, or fails a required criterion.

## Keep judgment separate from execution

The Oracle cannot run product actions, change applicability facts, edit the rubric, or supply missing evidence. It decides only the current obligation. Main evaluates the Scenario success expression from obligation results after every Oracle result passes provenance checks.
