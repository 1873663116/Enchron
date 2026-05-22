# Documentation Cleanup and Maintenance Plan

Status: Active plan.
Created: 2026-05-22.
Scope: Documentation structure, stale document cleanup, routing-doc integration.
Exit: Archive or delete this plan after completion.

## Goal

Reduce documentation maintenance debt.

This pass updates the playback routing documentation while also cleaning stale
references, clarifying document ownership, and preventing duplicate normative
sources.

## Non-Goals

- No Swift code changes.
- No implementation of `AVPlayerAdapter`.
- No implementation of `PlaybackEngineRouter`.
- No broad rewrite of archived historical material.
- No new reference document unless it has a durable purpose not covered by
  architecture, product philosophy, language, or contract docs.

## Document Ownership Model

### `ARCHITECTURE.md`

Owns stable architecture boundaries, module responsibilities, dependency
direction, cross-module invariants, and deliberate absences.

It must not become a changelog, phase summary, issue archive, or implementation
guide.

### `docs/product_philosophy.md`

Owns product principles and strategic product tradeoffs.

It must not define API contracts, test matrices, or adapter implementation
details.

### `docs/ubiquitous_language.md`

Owns shared vocabulary.

It must not contain strategy essays or implementation plans.

### `docs/contracts/`

Owns active normative contracts that constrain current or planned
implementation.

A contract is allowed only when code or future code must obey it.

### `docs/plans/active/`

Owns active execution plans only.

A plan must have an exit condition. Completed plans must be archived or deleted.

### `docs/reference/`

Owns durable investigations, diagnostics, and technical references.

Reference documents are not normative unless explicitly linked by a contract or
architecture document.

### `docs/archive/`

Owns historical material.

Archived files should not be linked from active architecture unless the link
explicitly says it is historical context.

### `docs/designs/`

Owns visual/design artifacts.

Design artifacts do not define architecture boundaries unless copied into
architecture/product docs.

### `docs/solutions/`

Owns reusable troubleshooting or solution notes.

If a solution note is obsolete or one-off, archive or delete it.

## Cleanup Procedure

### Step 1: Inventory

Run:

```bash
find docs -type f | sort
find .agents/skills/visionos-platform -type f | sort
rg -n "docs/contracts|frontend-backend-contract|AV reference path|debug-only|diagnostic-only|phase|v0\\.|TODO|obsolete|deprecated|已废弃|过期" ARCHITECTURE.md docs .agents/skills/visionos-platform
```

Create a local inventory table during the task with:

- path
- category
- current owner
- keep / rewrite / archive / delete
- reason
- active inbound links

Do not commit the inventory table unless it becomes useful documentation.

### Step 2: Fix broken active references

Replace links to missing files.

Do not keep references to `docs/contracts/frontend-backend-contract.md` unless
that file is created in the same PR. This task should not create it.

### Step 3: Consolidate routing documentation

Do not create a separate
`docs/reference/2026-05-22-deterministic-playback-engine-routing.md`.

Routing ownership is:

- strategy: `docs/product_philosophy.md`
- vocabulary: `docs/ubiquitous_language.md`
- architecture boundary: `ARCHITECTURE.md`
- normative contract: `docs/contracts/playback-engine-routing.md`
- agent checkpoint: `.agents/skills/visionos-platform/references/playback-media.md`
- HDR diagnostic distinction: `docs/reference/window-hdr-edr-diagnostics-guide.md`

### Step 4: Stale document handling

Keep when:

- the file defines current product direction;
- the file defines current architecture boundaries;
- the file is a live contract;
- the file is still referenced by active code, tests, agents, or plans;
- the file is a durable diagnostic reference.

Rewrite when:

- the topic is still current but the language is stale;
- the file duplicates a normative source but still contains useful facts;
- the file mixes strategy, contract, and implementation.

Archive when:

- the file is historically useful but no longer active;
- the file describes an old phase, old plan, old investigation, or old QA result.

Delete when:

- the file is one-off, obsolete, unreferenced, and not useful as history;
- the file contradicts current architecture and has no durable diagnostic value;
- the file duplicates a newer canonical doc.

### Step 5: Add document headers

Every active markdown doc touched in this task should have a short header
stating:

- purpose
- status
- owner/scope
- what this file is not

### Step 6: Verify

Run:

```bash
git diff --name-only
git diff --check
rg -n "docs/contracts/frontend-backend-contract|AV reference path|debug-only|diagnostic-only|isolated and diagnostic" ARCHITECTURE.md docs .agents/skills/visionos-platform
rg -n "PlaybackEngine|PlaybackEngineRoute|PlaybackEngineRouter|AppleNativeMedia|OpenFormatMedia|appleAV|mpv-safe|Apple-native|single-engine|单引擎" ARCHITECTURE.md docs .agents/skills/visionos-platform
rg -n "PlayerUI.*mpv|PlayerUI.*AV|UI.*engine|PlaybackMode.*engine|AVKit.*state machine|system player.*state machine" ARCHITECTURE.md docs .agents/skills/visionos-platform
bun .agents/skills/visionos-platform/scripts/verify-skill-docs.ts
test ! -f docs/reference/2026-05-22-deterministic-playback-engine-routing.md
test -f docs/contracts/playback-engine-routing.md
test -f docs/plans/active/2026-05-22-documentation-cleanup-and-maintenance.md
```

If the skill-doc script fails because a touched reference file lacks required
sections, fix the touched file.

If it fails because of pre-existing unrelated reference files, record the
failure in the PR notes and do not expand this task into a full skill-doc
rewrite unless the failure blocks the changed playback reference.

## Definition of Done

- `ARCHITECTURE.md` no longer links to missing contract files.
- Playback routing invariants exist in `ARCHITECTURE.md`.
- Product strategy exists in `docs/product_philosophy.md`.
- Routing terms exist in `docs/ubiquitous_language.md`.
- The only normative routing contract is
  `docs/contracts/playback-engine-routing.md`.
- No separate routing reference strategy doc is created.
- The visionOS playback skill reference reflects the new production direction.
- The HDR diagnostics guide still treats Apple reference playback as diagnostic
  evidence, not as the production route contract.
- This cleanup plan has a clear archive/delete exit.
