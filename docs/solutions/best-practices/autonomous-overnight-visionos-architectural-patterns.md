---
title: "visionOS Autonomous Development: Architectural Patterns and Structural QA"
date: 2026-04-02
category: best-practices
module: PlaybackCore, FileBrowsing, PlayerUI, App
problem_type: best_practice
component: development_workflow
severity: medium
applies_when:
  - Building visionOS apps with multi-phase playback launch flows
  - Running autonomous multi-round development without human supervision
  - Testing on visionOS Simulator where interactive CLI API is unavailable
  - Splitting resource-acquiring operations into prepare/commit phases
  - Managing cross-module dependencies in Clean Architecture
tags:
  - visionos
  - autonomous-development
  - structural-qa
  - clean-architecture
  - swift6
  - preparedplayback-ttl
  - closure-injection
  - coordinator-pattern
  - liquid-glass
  - pipeline-state-machine
---

# visionOS Autonomous Development: Architectural Patterns and Structural QA

## Background

Enchron (visionOS video player) underwent an 11-round autonomous overnight development cycle covering a full UI/UX rewrite (Liquid Glass migration, video detail view, timeline unification, immersive space global entry) and design-doc-complete feature implementation (playback behavior settings, resume prompts, progress indicators, screen position controls, Photo Library integration, cache cleanup, network reconnect). 35 files changed, +2549/-681 lines. The following patterns emerged from solving real problems under autonomous constraints.

## Guidance

### 1. PreparedPlayback TTL Pattern

When splitting a resource-acquiring operation into "prepare" and "commit" phases with user interaction in between, wrap prepared resources in a value type with a creation timestamp and fixed TTL.

```swift
struct PreparedPlayback {
    let request: PlaybackLaunchRequest
    let metadata: PlaybackMediaMetadata
    let preparedAt: Date
    var isExpired: Bool { Date().timeIntervalSince(preparedAt) > 60 }
}
```

The coordinator publishes `currentPreparation: PreparedPlayback?` as a published property. The detail view observes it read-only. On navigation away or timeout, the coordinator sets it to `nil` and tears down warmup resources. On confirm, the coordinator consumes the preparation and transitions to active playback.

Key rules:
- TTL checked lazily (on access) and eagerly (via timer or next user interaction)
- Coordinator, not the view, owns cancellation logic
- `PreparedPlayback` is a value type — no ownership ambiguity or reference cycles

### 2. Closure Injection for Cross-Module Dependency

When an inner module (PlaybackCore) needs a capability from an outer module (FileBrowsing), inject a closure at the app assembly root instead of importing the outer module.

```swift
// PlaybackCore — declares need, knows nothing about FileBrowsing
final class PlaybackLaunchCoordinator {
    private let nextFileProvider: (String) -> PlayableFileInfo?
    
    func onPlaybackFinished(currentFileID: String) {
        guard let next = nextFileProvider(currentFileID) else { return }
        preparePlayback(next)
    }
}

// App module (composition root) — sees both modules
let coordinator = PlaybackLaunchCoordinator(
    nextFileProvider: { currentID in fileBrowsingService.fileAfter(id: currentID) }
)
```

Why closures over protocols: for a single function, a protocol adds a file, a conformance, and a type name that exists only to satisfy the pattern. Promote to a protocol when the surface grows to 2-3 functions.

### 3. Coordinator as Single Source of Truth

All playback state mutations go through PlaybackLaunchCoordinator. Views never create independent `@State` for playback-related data. Views read coordinator's published properties via `@Environment`.

```swift
// View reads, never writes
struct VideoDetailView: View {
    @Environment(PlaybackLaunchCoordinator.self) var coordinator
    
    var body: some View {
        if let prep = coordinator.currentPreparation {
            MetadataDisplay(prep.metadata)
            Button("Play") { coordinator.confirm() }
        }
    }
}
```

Rules: (1) Coordinator is `@Observable` injected at app root. (2) Views bind read-only. User actions call coordinator methods. (3) No view holds a local copy of playback state. (4) Only the coordinator talks to the mpv engine.

### 4. ResumePolicy Three-State Design

Model resume behavior as a three-case enum, not a boolean:

```swift
enum ResumePolicy {
    case always  // Automatically resume if saved position > 5s
    case never   // Always start from beginning
    case ask     // Show UI letting user choose
}
```

The 5-second threshold prevents resuming from trivially early positions. The detail view renders dual buttons (Resume / Start Over) only when policy is `.always` or `.ask` AND saved position exceeds threshold.

### 5. Liquid Glass Selective Migration

Apply `.glassBackgroundEffect()` to chrome-level containers (data source chips, connection bars, empty states, settings sections, scene cards). Do NOT apply to content surfaces where primary focus is the content itself. Do NOT re-apply to surfaces that already have glass.

Migration per module: inventory backgrounds -> classify chrome vs content -> replace chrome with glass -> verify text contrast and no nested double-blur.

### 6. Timeline Unification: Delete Rather Than Abstract

When two components serve the same role at different complexity levels, delete the complex one and redistribute its 2-3 useful features into the simple one. Enchron deleted a 438-line DetailedTimelineView, moved precise time labels inline (show on drag), and moved frame stepping to secondaryControlRow. Net result: -438 lines, zero feature loss.

The test: if the complex component's unique value can be expressed as small additions to the simple component, delete and redistribute.

### 7. Immersive Space Global Entry

Global mode toggles belong in the app-level toolbar, not buried in settings. Use a `.compact` style variant for toolbar placement. Hide during active playback to avoid conflicting with playback-specific controls.

### 8. Structural QA When Interactive Testing Is Unavailable

visionOS Simulator lacks CLI interaction API. Define a structural verification matrix:

| Check Category | What It Verifies | How |
|---|---|---|
| Protocol conformance | Types implement required protocols | Build success + grep conformance |
| Navigation wiring | Views reachable from entry points | Static NavigationStack/Link analysis |
| Environment injection | Dependencies injected at assembly root | Grep `.environment()` at app root |
| Regression coverage | Known regressions have checks | Cross-ref REGRESSION.md |
| Build success | No compile errors | `xcodebuild build` |
| Runtime log analysis | No crashes at launch | Parse simulator logs |

Structural checks catch ~60-70% of integration bugs. Explicitly mark "interactive validation deferred to human" for visual/touch verification.

### 9. Single-Goal-Per-Round Discipline

Each autonomous round has exactly ONE goal. If larger than expected, output "refined goal + partial progress" and let next round continue.

Observed progression: Diagnose (R1-2) -> Plan (R3) -> CEO Review (R4) -> Eng Review (R5) -> Execute (R6-8) -> Verify (R9-10) -> Complete (R11).

### 10. Pipeline State Machine

```
PLANNING -> REVIEWING -> EXECUTING -> VERIFYING -> COMPLETING
```

Transition rules enforced via overnight-log.md:
- PLANNING -> REVIEWING: Plan document complete
- REVIEWING -> EXECUTING: Review pass logged with no blockers
- EXECUTING -> VERIFYING: All changes committed, build succeeds
- VERIFYING -> COMPLETING: Structural QA passes, regression set updated
- Any -> BLOCKED: Safety issue or 3x consecutive failure

## Why This Matters

These patterns reinforce each other:
- **PreparedPlayback TTL** works because the **Coordinator is the single source of truth** — one place manages the preparation lifecycle
- **Closure Injection** enables the coordinator pattern without violating module boundaries
- **Structural QA** is feasible because Clean Architecture makes protocol conformance checkable, DI greppable, navigation declarative
- **Single-Goal-Per-Round** makes the **Pipeline State Machine** practical — each round maps to exactly one state

The meta-lesson: architectural discipline at code level (Clean Architecture, single source of truth, minimal abstraction) directly enables process discipline at development level (autonomous rounds, structural verification, state-machine-gated progression).

## When to Apply

- Building apps with multi-phase resource lifecycle (prepare/commit with user interaction)
- Managing cross-module dependencies in Clean Architecture projects
- Running autonomous multi-round development workflows
- Testing on platforms without programmatic UI testing capability
- Migrating visual design systems (glass, vibrancy, blur) across existing apps
- Choosing between abstracting and deleting redundant components

## Examples

See code examples inline in each pattern above. Key before/after:

**Before** (single-step launch):
```swift
func launchPlayback(_ file: PlayableFileInfo) {
    mpvEngine.loadAndPlay(PlaybackLaunchRequest(file: file))
}
```

**After** (two-phase with TTL + closure injection + coordinator SSOT):
```swift
// Prepare phase
func preparePlayback(_ file: PlayableFileInfo) async throws {
    let metadata = try await metadataService.fetch(file)
    mpvEngine.warmup(PlaybackLaunchRequest(file: file))
    currentPreparation = PreparedPlayback(request: request, metadata: metadata, preparedAt: Date())
}

// Confirm phase (with auto-next via injected closure)
func confirmPlayback() {
    guard let prep = currentPreparation, !prep.isExpired else {
        currentPreparation = nil; return
    }
    mpvEngine.play(prep.request)
    currentPreparation = nil
}

func onPlaybackFinished(currentFileID: String) {
    guard let next = nextFileProvider(currentFileID) else { return }
    preparePlayback(next)
}
```

## Related

- `docs/plans/2026-04-02-001-feat-phase1-3-ui-ux-rewrite-plan.md` — Implementation plan for Phase 3
- `docs/plans/2026-04-02-arch.md` — Architectural review of PreparedPlayback and coordinator patterns
- `docs/qa-reports/qa-report-enchron-2026-04-02.md` — Structural QA report with 25+ checks
- `REGRESSION.md` — REG-080-096 covering new patterns
- `workspace-agents/skills/liquid-glass-design/SKILL.md` — Liquid Glass API reference
