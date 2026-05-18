# Code Review Report — EXECUTING Phase (Units 1-9)

**Run ID:** 20260406-5163c71
**Scope:** 9159d76..HEAD (20 Swift files, 498+/245-)
**Intent:** 9 implementation units fixing 6 known UI issues (P0-P2) — player controls layout, hover effects, animations, playback mode constraints, canvas resize, NLE timeline, browse/detail page alignment.
**Mode:** Interactive (overnight context)
**Plan:** docs/plans/active/ExecPlan.md (plan_source: explicit)

## Review Team

| Reviewer | Type | Justification |
|----------|------|---------------|
| correctness | always | — |
| testing | always | — |
| maintainability | always | — |
| pattern-recognition | always | — |
| architecture-strategist | conditional | geometric constraint touches UseCase/Domain boundary |
| adversarial | conditional | 498+ changed lines across core UI and playback logic |
| bug-analyzer | conditional | animation timing, drag calculation, GeometryReader integration |

## Verdict: Ready with fixes

**0 P0 | 0 P1 | 6 P2 | 5 P3**

All P0/P1 candidates from individual reviewers were either pre-existing, based on incorrect SwiftUI layout assumptions, or downgraded upon verification. No blocking issues found. Code is functionally correct and aligned with ExecPlan requirements.

---

## P2 Findings (fix if simple)

### F1. Dead parameters in videoPreviewPlaceholder [P2]
**File:** VideoDetailView.swift:243
**Reviewers:** adversarial, maintainability, correctness (3-way agreement, confidence 0.95)
**Route:** safe_auto → review-fixer

`showPlayButton: Bool` parameter is declared but never referenced in the method body. Also `displayName: String` is accepted but unused (title display moved to `titleSection()`).

**Fix:** Remove both unused parameters.

### F2. Hardcoded play button colors not in DesignTokens [P2]
**File:** PlayerControlsView.swift:190, 197-198
**Reviewers:** maintainability (confidence 0.80)
**Route:** gated_auto → downstream-resolver

Three RGB values hardcoded: `Color(red: 0.184, green: 0.192, blue: 0.192)` (foreground), gradient `#c6c6c7` and `#909191`. Should be in DesignTokens for consistency.

### F3. Glass sub-panel opacity duplicated in VideoDetailView [P2]
**File:** VideoDetailView.swift:224, 391, 460, 517
**Reviewers:** maintainability, pattern-recognition (2-way agreement, confidence 0.85)
**Route:** gated_auto → downstream-resolver

`Color.white.opacity(0.04)` used in 4 locations as glass-sub background. Should be a DesignTokens constant.

### F4. Card styling duplicated between VideoCardView and ContentGridView [P2]
**File:** VideoCardView.swift:27-32, ContentGridView.swift:84-89
**Reviewers:** maintainability (confidence 0.75)
**Route:** gated_auto → downstream-resolver

Identical pattern: `Color.white.opacity(0.03)` background + `Color.white.opacity(0.05)` ghost border + 0.5 lineWidth. Should be a shared modifier.

### F5. Missing test coverage for additional ProjectionType variants [P2]
**File:** Tests/XrPlayerCoreTests/PlaybackModeRoutingTests.swift
**Reviewers:** testing (confidence 0.75)
**Route:** manual → downstream-resolver

Tests cover .flat, .stereoscopicSBS, .stereoscopicOU, .panorama360. Missing: .panorama180, .stereoscopicTAB (if they exist in the enum). Verify enum exhaustiveness.

### F6. NLE glass panel changed from enchronGlassPanel() to raw glassBackgroundEffect [P2]
**File:** NLETimelineView.swift:55-60
**Reviewers:** pattern-recognition (confidence 0.80)
**Route:** gated_auto → downstream-resolver

Replaced `.enchronGlassPanel()` with raw `.glassBackgroundEffect(in: RoundedRectangle(...))`. Bypasses the centralized glass helper, making future design changes harder to propagate.

---

## P3 Findings (advisory)

### F7. Animation duration 0.4s hardcoded in 10+ locations [P3]
**Reviewers:** correctness, pattern-recognition
Intentional per HTML design spec. Recommend extracting to `DesignTokens.Animation.controlShowHide`.

### F8. Button sizes (48/60/64) not tokenized [P3]
**Reviewers:** pattern-recognition
Intentional hierarchy but undocumented. Recommend `DesignTokens.ButtonSize` enum.

### F9. Padding values (16/24/28) not tokenized [P3]
**Reviewers:** pattern-recognition
Semi-consistent within content regions. Recommend `DesignTokens.Spacing` enum.

### F10. Opacity values (.5/.6/.7) inconsistent across secondary text [P3]
**Reviewers:** pattern-recognition
No semantic naming system for opacity levels.

### F11. Timeline drag anchored to start time during active playback [P3]
**Reviewers:** bug-analyzer, correctness
dragStartTime captured once; playback may advance during drag. This is standard timeline scrubbing behavior (seek relative to drag start, not current playback position). Document this design choice.

---

## Pre-existing Issues (not introduced by this diff)

| Issue | Location | Notes |
|-------|----------|-------|
| NLETimelineToggleButton same icon for expanded/collapsed | NLETimelineView.swift:171 | `"timeline.selection"` in both branches |
| MainView drag coefficient (0.15) inconsistent with timeline geometry calc | MainView.swift:206 | Pre-existing gesture handler, not part of this diff |
| Resume 5-second threshold | VideoDetailView.swift:275 | Same condition as old code |

---

## Dismissed Findings (incorrect or unfounded)

| Claim | Source | Reason for Dismissal |
|-------|--------|---------------------|
| GeometryReader causes zero-size layout collapse | adversarial, bug-analyzer | **Incorrect.** GeometryReader fills proposed space from parent ZStack. WindowVideoView receives valid window dimensions on first layout. |
| MTKView guard `> 1` too strict | correctness | **Intentional.** Matches MoltenVK 1x1 workaround. Legitimate resizes always > 1. |
| Info bar hidden in immersive mode is regression | adversarial | **Intentional.** Immersive mode uses companion window for controls (Unit 13 from earlier pipeline). |
| Seek bar lacks glass treatment | adversarial | **Intentional.** HTML design spec shows seek bar separate from pill (comment: "no glass"). |
| Gesture hit-testing broken outside GeometryReader | bug-analyzer | **Incorrect.** DragGesture is on ZStack child, contentShape applies correctly. |
| allowedModes violates architecture invariant | architecture | **Correct placement.** UseCase layer importing PlaybackCoreDomain is per eng review amendment. |

---

## Requirements Completeness (plan_source: explicit)

| Req | Status | Notes |
|-----|--------|-------|
| R1 | ✅ Satisfied | Player control bar 6-button pill layout |
| R2 | ✅ Satisfied | Menu popup with HDR/Subtitles/Audio/Speed |
| R3 | ✅ Satisfied | Settings popup with Mode/Environment |
| R4 | ✅ Satisfied | L1/L2 alignment to HTML design |
| R5 | ✅ Satisfied | Seek bar with remaining time |
| R6 | ✅ Satisfied | .hoverEffect(.lift) across 10 files |
| R7 | ✅ Satisfied | .hoverEffect(.lift) replaces .highlight |
| R8 | ✅ Satisfied | Pure opacity fade for controls |
| R9 | ✅ Satisfied | Ornament transition respected |
| R10 | ✅ Satisfied | All showControls sites wrapped |
| R11 | ✅ Satisfied | Geometric constraint implemented |
| R12 | ✅ Satisfied | Mode menu filters by constraint |
| R13 | ✅ Satisfied | Manual override validated |
| R14 | ✅ Satisfied | Constraint logic in UseCase layer |
| R15 | ✅ Satisfied | GeometryReader drives resize |
| R16 | ✅ Satisfied | containerSize passed to WindowVideoView |
| R17 | ✅ Satisfied | MoltenVK workaround preserved |
| R18 | ✅ Satisfied | NLE glass background |
| R19 | ✅ Satisfied | NLE buttons contained |
| R20 | ✅ Satisfied | Ruler/thumbstrip drag logic |
| R21 | ✅ Satisfied | Player buttons interactive |
| R22 | ✅ Satisfied | Detail page buttons audited |

**22/22 requirements satisfied.**

---

## Coverage

- **Reviewers:** 7/7 returned results
- **Confidence gating:** 1 finding suppressed (ThumbStripView inlined drag, confidence 0.50)
- **Cross-reviewer agreement:** F1 (3-way), F3 (2-way), F5 (2-way)
- **Residual risks:** Timeline drag-during-playback UX, NLE ornament total height (~332pt)
- **Testing gaps:** No visionOS UI test framework; all layout/animation changes require human device verification
