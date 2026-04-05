---
title: "TestPlan: Known Issues Fix — P0~P2 UI Alignment"
type: test
status: active
date: 2026-04-05
origin: docs/plans/active/ExecPlan.md
---

# TestPlan: Known Issues Fix — P0~P2 UI Alignment

## Overview

Dual-track verification for the 6 known UI issues fix. Agent self-checks cover compilation, structure guards, and automated assertions. Human verification covers visual fidelity, interaction quality, and visionOS-specific behavior that simulators can't fully validate.

## Agent Self-Check (Automated)

### SC-1: Build Success
- [ ] `xcodebuild build` succeeds with zero errors
- [ ] No new warnings in modified files

### SC-2: Structure Guards
- [ ] `grep -r "hoverEffect(.highlight)" XrPlayer/` returns zero matches (all replaced with `.lift`)
- [ ] `grep -r "PlaybackMode.allCases" XrPlayer/PlayerUI/Views/` returns zero matches in mode menu context (filtered by constraint)
- [ ] `grep -r "showControls = " XrPlayer/MainView.swift` — every occurrence wrapped in `withAnimation` (except initializer)
- [ ] `DecidePlaybackModeUseCase` contains validation logic for manual override (not a bare `return override`)

### SC-3: Regression Guards
- [ ] REG-109 (playback mode auto-route): panoramic video auto-routes to `.panorama`
- [ ] REG-109: flat video auto-routes to `.window`
- [ ] REG-109: stereo 3D video auto-routes to `.window` (no immersive environment active)
- [ ] Mode constraint: `PlaybackMode.allowedModes(for: .flat)` returns `[.window, .immersive]`
- [ ] Mode constraint: `PlaybackMode.allowedModes(for: .panorama360)` returns `[.window, .immersive, .panorama]`
- [ ] Mode constraint: `DecidePlaybackModeUseCase` with manualOverride `.panorama` + projectionType `.flat` returns `.window` (clamped)
- [ ] Mode constraint: When projectionType is not yet detected (default), `allowedModes` returns `[.window, .immersive]` (safe default)

### SC-4: Snapshot UI Verification (Simulator)
- [ ] `mcp__XcodeBuildMCP__screenshot` captures player controls in visible state
- [ ] `mcp__XcodeBuildMCP__snapshot_ui` confirms button hit targets are not overlapped

---

## Acceptance Criteria by Requirement

### R1: Player Control Bar Layout
- [ ] **[Agent]** Control bar is pill-shaped (Capsule clip shape)
- [ ] **[Agent]** 5 buttons in order: Menu, Rewind 10s, Play/Pause, Forward 10s, Settings
- [ ] **[Human]** Visual layout matches `player.html` footer — pill shape, button sizes, spacing
- [ ] **[Human]** Play/Pause button is visually larger (64pt) with gradient background

### R2: Menu Popup (Left)
- [ ] **[Agent]** Menu button triggers popup with Subtitles, Audio Track, Playback Speed items
- [ ] **[Human]** Popup opens upward from Menu button, expanding leftward
- [ ] **[Human]** Sub-menus cascade to the left with correct animation

### R3: Settings Popup (Right)
- [ ] **[Agent]** Settings button triggers popup with Playback Mode, Environment items
- [ ] **[Human]** Popup opens upward from Settings button, expanding rightward
- [ ] **[Human]** Sub-menus cascade to the right with correct animation

### R4: Level 1 & 2 Layout Alignment
- [ ] **[Human]** Browsing page card grid: 3 columns, correct spacing, 16:9 cards
- [ ] **[Human]** Detail page: two-column layout matching `variant-AB-combined.html`
- [ ] **[Human]** Navigation sidebar icons are properly sized and positioned
- [ ] **[Agent]** If >10 files changed, flagged for separate PR

### R5: Seek Bar
- [ ] **[Agent]** Seek bar positioned above control bar pill
- [ ] **[Human]** Time labels: current time (left), remaining (right), monospaced digits
- [ ] **[Human]** Progress track visible with correct colors and knob

### R6 + R7: Hover Effect Shape
- [ ] **[Agent]** Zero occurrences of `.hoverEffect(.highlight)` in codebase
- [ ] **[Agent]** All hover effects use `.hoverEffect(.lift)`
- [ ] **[Human/Device]** Circular button shows circular hover lift
- [ ] **[Human/Device]** Rectangular button shows rectangular hover lift

### R8 + R9 + R10: Controls Animation
- [ ] **[Agent]** All `showControls` mutation sites use `withAnimation(.easeInOut(duration: 0.4))`
- [ ] **[Agent]** `.transition(.opacity)` present on controls content
- [ ] **[Human/Device]** Controls appear with pure opacity fade — no position shift, no scale
- [ ] **[Human/Device]** Controls disappear with pure opacity fade
- [ ] **[Human/Device]** Auto-hide (8s) triggers same smooth fade

### R11 (Corrected): Geometric Mode Constraint
- [ ] **[Agent]** `PlaybackMode.allowedModes(for:)` exists and returns correct sets
- [ ] **[Agent]** Unit test: flat → `[window, immersive]`
- [ ] **[Agent]** Unit test: stereoscopicSBS → `[window, immersive]`
- [ ] **[Agent]** Unit test: panorama360 → `[window, immersive, panorama]`
- [ ] **[Human]** Playing 2D video: Panorama option not available in mode menu
- [ ] **[Human]** Playing 2D video: Immersive (virtual cinema) option IS available and works
- [ ] **[Human]** Playing panoramic video: All 3 mode options available

### R12: Mode Menu Filtering
- [ ] **[Agent]** Mode menu does NOT use `PlaybackMode.allCases`
- [ ] **[Agent]** Mode menu filters based on current `projectionType`
- [ ] **[Human]** Only valid modes shown in Settings > Playback Mode

### R13: Manual Override Validation
- [ ] **[Agent]** `DecidePlaybackModeUseCase` validates override against `allowedModes`
- [ ] **[Agent]** Invalid override (e.g., `.panorama` for flat video) clamped to `.window`
- [ ] **[Agent]** Valid override passes through normally

### R14: Constraint in PlayerUI
- [ ] **[Agent]** All constraint logic resides in `XrPlayer/PlayerUI/` directory
- [ ] **[Agent]** No mode constraint code in `PlaybackCore/` or `SpatialScene/`

### R15 + R16 + R17: Video Canvas Resize
- [ ] **[Agent]** `GeometryReader` wraps `WindowVideoView` usage
- [ ] **[Agent]** Size parameter passed to `updateUIView`
- [ ] **[Agent]** MoltenVK 1x1 workaround still present and unchanged
- [ ] **[Human/Device]** Dragging window edge resizes video canvas proportionally
- [ ] **[Human/Device]** No black bars or incorrect aspect ratio after resize

### R18: NLE Glass Background
- [ ] **[Agent]** NLE panel has glass background modifier applied
- [ ] **[Human]** Glass effect visible and matches design (dark with blur)

### R19: NLE Button Containment
- [ ] **[Agent]** `.clipped()` or clip shape applied to NLE panel container
- [ ] **[Human]** No buttons or UI elements overflow panel boundaries

### R20: NLE Drag Logic
- [ ] **[Agent]** Ruler area responds to horizontal `DragGesture`
- [ ] **[Human]** Dragging ruler scrolls timeline content
- [ ] **[Human]** Playhead stays fixed at center during drag

### R21: Player Page Button Interactivity
- [ ] **[Agent]** All 5 control buttons have tap handlers connected
- [ ] **[Agent]** No `.allowsHitTesting(false)` blocking control buttons
- [ ] **[Human]** Every button on player page responds to tap/gaze in device

### R22: Detail Page Button Audit
- [ ] **[Agent]** Audit documented: which buttons work, which don't, and why
- [ ] **[Human]** Functional buttons respond correctly
- [ ] **[Human]** Non-functional buttons documented with clear reason (not implemented vs bug)

---

## Human Verification Checklist (for device testing)

After all agent self-checks pass, verify on visionOS device:

1. **Player controls visual fidelity**
   - Pill shape, button sizes, gradient play button match HTML design
   - Seek bar above controls with time labels
   - Glass background effect visible and consistent

2. **Menu interactions**
   - Menu popup cascades left, Settings popup cascades right
   - Sub-menu items are tappable and apply changes
   - Popups dismiss correctly

3. **Hover effects (device only)**
   - Gaze at circular button → circular lift effect
   - Gaze at rectangular button → rectangular lift effect
   - No mismatched shapes

4. **Controls animation (device only)**
   - Show controls: pure opacity fade in, zero movement
   - Hide controls: pure opacity fade out, zero movement
   - Auto-hide after 8 seconds: smooth fade

5. **Mode constraint**
   - Load 2D video → Settings > Playback Mode shows Window + Immersive only
   - Load panoramic video → shows all 3 modes
   - Immersive mode works for 2D video (virtual cinema)

6. **Window resize**
   - Drag window edge → video canvas resizes proportionally
   - No artifacts or black bars

7. **NLE timeline**
   - Glass panel visible
   - No button overflow
   - Drag on ruler scrolls timeline

8. **Browse & detail pages**
   - Card grid matches HTML layout
   - Detail page two-column layout correct
   - All expected buttons functional
