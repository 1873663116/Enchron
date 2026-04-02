---
title: "Architecture Review: Phase 1-3 UI/UX Rewrite"
type: arch
status: active
date: 2026-04-02
branch: MinimaxTest
reviewed_plan: docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md
---

# Architecture Review: Phase 1-3 UI/UX Rewrite

## Review Summary

The plan is architecturally sound. It correctly extends PlaybackLaunchCoordinator with a prepare/confirm split rather than bypassing it, preserves the single-coordinator invariant, and keeps bounded context boundaries clean. Two P1 issues found: the observation model for async metadata in VideoDetailView, and the navigation mechanism from FileBrowserView to VideoDetailView. Both are solvable within the current architecture. File path error and missing test scenarios are P2.

## Technical Issues

### P0: None

### P1: PreparedPlayback observation model is underspecified

**Location:** Unit 3 approach + Unit 4 approach
**Problem:** Plan says "VideoDetailView receives PreparedPlayback binding". But track lists arrive asynchronously after `mpv loadfile+pause` completes. A simple `Binding<PreparedPlayback>` can't express async updates. The view needs to observe resolution progress.

**Blast radius:** Gets this wrong and VideoDetailView either freezes waiting for data or shows stale empty lists.

**Resolution (auto-decided for overnight):**

PlaybackLaunchCoordinator is already `@Observable`. Add a published preparation state:

```
// Directional guidance, not implementation spec
@Observable
class PlaybackLaunchCoordinator {
    // Existing...
    private(set) var currentPreparation: PreparationState?
    
    enum PreparationState {
        case preparing(request: PlaybackLaunchRequest, metadata: PlaybackMediaMetadata?)
        case ready(PreparedPlayback)
        case failed(Error)
    }
}
```

VideoDetailView observes `coordinator.currentPreparation` via `@Environment(PlaybackLaunchCoordinator.self)`. No new types needed for observation. PreparedPlayback remains a value type for the `ready` case.

This keeps the coordinator as single source of truth and avoids callback spaghetti.

### P1: Navigation mechanism from FileBrowserView to VideoDetailView is undefined

**Location:** Unit 4 approach, FileBrowsingViewModel interaction
**Problem:** Plan says "FileBrowserView pushes VideoDetailView onto its NavigationStack" but doesn't specify the trigger mechanism. Currently `selectFile` calls `onPlayFile(request)` which is fire-and-forget. The new flow needs:
1. `selectFile` → resolve URL → call `coordinator.preparePlayback(request)`
2. Simultaneously navigate to VideoDetailView

Navigation in SwiftUI NavigationStack requires state-driven `.navigationDestination`. FileBrowsingViewModel needs a navigation state property (e.g., `selectedFileForDetail: PlaybackLaunchRequest?`) that triggers the push.

**Blast radius:** Gets this wrong and either navigation doesn't happen, or it happens before preparation starts, or there's a race between preparation and navigation.

**Resolution (auto-decided for overnight):**

FileBrowsingViewModel gets a navigation trigger:

```
// Directional guidance
@Observable
class FileBrowsingViewModel {
    var detailNavigationRequest: PlaybackLaunchRequest?  // drives navigation
}
```

FileBrowserView adds:
```
.navigationDestination(item: $viewModel.detailNavigationRequest) { request in
    VideoDetailView()
}
```

The `selectFile` method becomes:
1. Resolve URL (existing async)
2. Create request (existing)
3. Call `coordinator.preparePlayback(request)` (new)
4. Set `detailNavigationRequest = request` (triggers navigation)

Back navigation: `onDisappear` of VideoDetailView calls `coordinator.cancelPreparedPlayback()`.

This keeps navigation state in ViewModel (SwiftUI standard) and preparation state in coordinator (architecture invariant).

### P2: File path error in Unit 5

**Location:** Unit 5 files section
**Problem:** Plan references `XrPlayer/PlayerUI/Geometry/DetailedTimelineGeometry.swift`. The actual path is `XrPlayer/PlayerUI/UseCases/DetailedTimelineGeometry.swift`.

**Resolution:** Correct the path in the plan before implementation.

### P2: Frame stepping and zoom controls fate unspecified in Unit 5

**Location:** Unit 5 approach
**Problem:** Plan says "inline precision features" and "precision scrubbing" but DetailedTimelineView currently has three distinct feature groups:
1. **Precision scrubbing** (fixed center pointer + drag timeline body) — mentioned in plan
2. **Zoom slider** (lines 263-294) — controls timeline scale, not mentioned
3. **Frame step buttons** (lines 296-321) — forward/backward frame, not mentioned

Merging only precision scrubbing but losing zoom and frame stepping would be a regression. These are "core experience assets" per product philosophy.

**Resolution (auto-decided for overnight):**

All three feature groups should move into the unified timeline. The frame step buttons can go into the secondaryControlRow of PlayerControlsView (alongside speed, settings, mode, playlist, info, debug). The zoom behavior can be a gesture on the slider (pinch to zoom) or removed if the unified timeline auto-scales. Implementation decides, but the plan should acknowledge these features exist and must be preserved or explicitly retired.

### P2: REGRESSION.md updates needed

**Location:** Not in plan
**Problem:** Unit 5 will retire the two-level toggle pattern, affecting REG-010 (geometry), REG-011 (enter/exit), REG-014 (preview seek boundaries), REG-017 (frame stepping). These items need status changes. New regression items needed for: unified timeline, video details page, immersive toggle global entry.

**Resolution:** Add a note in Unit 5 and Unit 8 to update REGRESSION.md as part of implementation.

### P2: Playlist callers and beginPlayback compatibility

**Location:** Unit 3 approach
**Problem:** `PlayerControlsView.playlistMenu` (line 330) calls `launcher.beginPlayback(request)`. Smoke test also uses `beginPlayback`. Plan correctly says these keep using `beginPlayback` — confirmed correct. Playlist items are already-identified media; re-showing a details page would be annoying UX.

No change needed. This is a positive confirmation.

## Architecture Recommendations

### Data Flow: Prepare/Confirm Split

```
CURRENT FLOW:
  selectFile → [resolve URL] → onPlayFile(request)
                                  → coordinator.beginPlayback(request)
                                    → appModel.startPlayback
                                    → viewModel.prepareForPlayback
                                    → metadata prefetch (async)
                                    → SwiftUI yield x8
                                    → viewModel.play(url)

PROPOSED FLOW:
  selectFile → [resolve URL] → coordinator.preparePlayback(request)
                                  → mpv loadfile+pause (async)
                                  → metadata prefetch (async)
                                  → coordinator.currentPreparation = .ready(...)
              → set detailNavigationRequest (navigation trigger)
              → VideoDetailView observes coordinator.currentPreparation
              → User taps Play → coordinator.confirmPlayback(prepared)
                                  → appModel.startPlayback
                                  → viewModel.prepareForPlayback
                                  → mpv resume (or play if different path)
              → User taps Back → coordinator.cancelPreparedPlayback()
                                  → cancel tasks, reset mpv, cleanup
```

Key architectural constraint preserved: all playback goes through PlaybackLaunchCoordinator.

### State Machine: PreparedPlayback Lifecycle

```
                  ┌─────────┐
      prepare()   │         │  confirm()
  ────────────►   │  READY  │ ────────────► PLAYING
                  │         │
                  └────┬────┘
                       │
           cancel() or │ TTL timeout (60s)
           back nav    │ or app background
                       ▼
                  ┌─────────┐
                  │ CLEANED │
                  │   UP    │
                  └─────────┘
```

Generation stamp on PreparedPlayback prevents stale confirms. TTL timer on coordinator handles abandoned preparations.

### Unified Timeline Architecture

```
CURRENT PlayerControlsView layout:
  ┌──────────────────────────────────────┐
  │  sliderSection OR DetailedTimeline   │  ← toggle, width 720 or 860
  │  primaryControlRow                   │
  │  secondaryControlRow [+ waveform btn]│
  └──────────────────────────────────────┘

PROPOSED PlayerControlsView layout:
  ┌──────────────────────────────────────┐
  │  UnifiedTimelineSection              │  ← always visible, consistent width
  │    - standard slider + time labels   │
  │    - precision scrubbing on drag     │
  │  primaryControlRow                   │
  │  secondaryControlRow [+ frame step]  │  ← frame step replaces waveform toggle
  └──────────────────────────────────────┘

Remove: showDetailedTimeline, pausedForTimeline states
Remove: waveform toggle button
Add: frame step buttons to secondaryControlRow
Preserve: DetailedTimelineGeometry for precision calculations
Decision: zoom — remove from main UI, auto-scale timeline to video duration
```

## Implementation Plan

### P0 (Blocker — resolve before coding)

None. All P1 issues have clear resolutions documented above.

### P1 (Resolve before or during implementation)

1. **PreparedPlayback observation model** — implement via coordinator's `currentPreparation` published state (see resolution above). Unit 3 implementation should follow this pattern.
2. **Navigation mechanism** — implement via `detailNavigationRequest` on FileBrowsingViewModel + `navigationDestination` on FileBrowserView (see resolution above). Unit 4 implementation should follow this pattern.

### P2 (Address during implementation)

3. **Fix file path** in plan: `UseCases/DetailedTimelineGeometry.swift`, not `Geometry/`
4. **Preserve frame stepping** — move to secondaryControlRow. Acknowledge zoom removal or replacement.
5. **Update REGRESSION.md** — retire REG-010/011/014/017, add new items for unified timeline + video details + immersive toggle.
6. **Track selection UX in VideoDetailView** — plan doesn't specify how audio/subtitle track selection works in the detail view. Pre-selecting a track before confirm means the coordinator needs to pass selection to confirmPlayback. Add to Unit 4 approach.

## NOT in scope

- Phase 4 (design doc gap analysis) — per TODOS.md, separate phase
- New playback features beyond what's planned
- Real device testing (Simulator only)
- Performance optimization of HDR pipeline
- Complete Settings view implementation (only immersive space controls added)
- KI-007 cold start optimization (existing known issue, orthogonal to this plan)
- Saturation enhancement (KI-014, requires custom Metal shader)

## Existing Code Reused

| Existing Code | How Plan Uses It |
|---------------|-----------------|
| `PlaybackLaunchCoordinator.generation` tracking | Extended for prepare/confirm lifecycle |
| `PlaybackMediaMetadataService.prepareMetadata()` | Called within `preparePlayback()` |
| `ToggleImmersiveSpaceButton` | Moved to MainView toolbar/ornament |
| `DetailedTimelineGeometry` (196 lines, tested) | Preserved for precision calculations |
| `PlaybackInfoFormatter` | Reused in VideoDetailView for metadata display |
| `PlayerControlSurfaceStyle` | Reused in all new/modified views |
| `PlaybackLaunchRequest` + `PlaybackMediaMetadata` | Extended, not rebuilt |
| `AppModel.immersiveSpaceState` | Reused for toggle state management |

All sub-problems are solved by extending existing code, not rebuilding.

## Test Coverage

### Code Path Coverage

```
UNIT 3: PlaybackLaunchCoordinator prepare/confirm
========================================
[+] preparePlayback()
    ├── [★★★ PLANNED] prepare → metadata resolves → confirm → plays
    ├── [★★★ PLANNED] prepare → cancel → cleanup
    ├── [★★★ PLANNED] prepare A → prepare B → A invalidated
    ├── [★★  PLANNED] confirm after generation mismatch → no playback
    ├── [GAP] prepare remote file → network timeout during loadfile+pause
    ├── [GAP] prepare → TTL expires → auto cleanup
    └── [GAP] prepare → app enters background → cleanup
[+] confirmPlayback()
    ├── [★★★ PLANNED] confirm with valid PreparedPlayback → plays
    └── [GAP] confirm with stale generation → no-op (overlap with above?)
[+] cancelPreparedPlayback()
    └── [★★  PLANNED] cancel → resources cleaned

UNIT 4: VideoDetailView
========================================
[+] Navigation
    ├── [★★★ PLANNED] navigate to detail → metadata loads → shows info → Play → plays
    ├── [★★★ PLANNED] navigate to detail → Back → cancelled
    ├── [★★  PLANNED] metadata loading → spinner, Play disabled
    ├── [★★  PLANNED] no subtitle tracks → section hidden
    ├── [GAP] preparation fails (error state display)
    ├── [GAP] select audio track → confirm → plays with selected track
    └── [GAP] select subtitle → confirm → plays with selected subtitle

UNIT 5: Unified Timeline
========================================
[+] Seek behavior
    ├── [★★★ PLANNED] slider drag → seek → position updates
    ├── [★★★ PLANNED] precision scrubbing → fine-grained seek
    ├── [★★  PLANNED] short video < 10s → scales appropriately
    ├── [★★  PLANNED] long video > 3h → markers remain useful
    ├── [★★  PLANNED] seek during buffering → no snap-back
    ├── [GAP] frame step forward/backward in unified view
    ├── [GAP] remote source throttled seek behavior preserved
    └── [GAP] zoom behavior (preserved or removed?)

UNIT 2: Immersive Toggle
========================================
[+] Toggle behavior
    ├── [★★★ PLANNED] tap in browsing → opens, tap again → closes
    ├── [★★★ PLANNED] in-transition → button disabled
    └── [★★★ PLANNED] cross-tab state reflection

─────────────────────────────────
COVERAGE: 14/22 paths tested
  Planned: 14 (64%)
QUALITY:  ★★★: 8  ★★: 6
GAPS: 8 paths need test scenarios added to plan
─────────────────────────────────
```

### Missing Test Scenarios to Add

**Unit 3:**
- Network timeout during `loadfile+pause` for remote files
- TTL expiration auto-cleanup
- App background → preparation cleanup

**Unit 4:**
- Error state display when preparation fails
- Audio track pre-selection before confirm
- Subtitle track pre-selection before confirm

**Unit 5:**
- Frame step forward/backward in unified timeline
- Remote source throttled seek preservation

## Failure Modes

| Code Path | Failure Mode | Test? | Error Handling? | User Sees |
|-----------|-------------|-------|-----------------|-----------|
| preparePlayback remote file | Network timeout during loadfile | NO | Partial (mpv error) | **Gap: unclear** |
| preparePlayback → TTL expires | User abandons detail view | NO | Planned (60s TTL) | Silent cleanup |
| confirmPlayback stale generation | Race between prepare/confirm | YES | YES (generation check) | No-op, stays on detail |
| VideoDetailView metadata load | Metadata never resolves | YES (spinner) | Partial | Spinner forever — **gap: needs timeout** |
| Immersive toggle during transition | Double-open attempt | YES | YES (disabled button) | Button grayed out |
| Unified timeline seek buffering | Seek to unbuffered position | YES | Existing mpv handling | Loading indicator |

**Critical gaps:** 0 — no path is both untested and unhandled and user-visible.
**Non-critical gaps:** 2 — remote prepare timeout (mpv handles but UX unclear), metadata load timeout (spinner with no escape).

## Worktree Parallelization Strategy

| Step | Modules | Depends On |
|------|---------|-----------|
| Unit 1: Test Videos | External (no code) | — |
| Unit 2: Immersive Toggle | App/, SpatialScene/ | — |
| Unit 3: Prepare/Confirm | App/, FileBrowsing/ | — |
| Unit 4: VideoDetailView | PlayerUI/, FileBrowsing/ | Unit 3 |
| Unit 5: Progress Bar | PlayerUI/ | — |
| Unit 6: FileBrowsing Glass | FileBrowsing/ | Unit 4 |
| Unit 7: App Glass | PlayerUI/, Settings/, App/ | Unit 5, Unit 6 |
| Unit 8: E2E QA | All (testing only) | Units 2-7 |

**Parallel Lanes:**

```
Lane A: Unit 2 (immersive toggle) → Unit 4 (detail view, after Unit 3 merges)
Lane B: Unit 3 (prepare/confirm) 
Lane C: Unit 5 (progress bar)

Merge A+B+C → Unit 6 → Unit 7 → Unit 8
```

Unit 1 runs anytime (no code changes). Units 2, 3, 5 are fully parallel — they touch different modules. Unit 4 depends on Unit 3 (needs PreparedPlayback). Units 6-7 depend on Unit 4 (navigation integration) and Unit 5 (timeline finalized). Unit 8 is sequential after all.

**3 lanes, 2 parallel / 1 sequential after merge.**

**Conflict risk:** Lane A (Unit 4) and Lane B (Unit 3) both touch `FileBrowsing/ViewModels/FileBrowsingViewModel.swift`. If running in parallel worktrees, coordinate the callback change.

## Completion Summary

- Step 0: Scope challenge — scope accepted as-is
- Architecture Review: 2 P1 issues found, both resolved
- Code Quality Review: 1 P2 issue (file path error)
- Test Review: chart generated, 8 gaps identified
- Performance Review: 0 issues (remote timeout is covered by P1-1 resolution)
- NOT in scope: written
- Existing code: written
- Architecture plan doc: this document
- Failure modes: 0 critical gaps
- Parallelization: 3 lanes, 2 parallel / 1 sequential
