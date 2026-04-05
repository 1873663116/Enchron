---
title: "fix: Align all UI to HTML design specs and resolve 6 known issues (P0-P2)"
type: fix
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-known-issues-fix-requirements.md
---

# fix: Align all UI to HTML design specs and resolve 6 known issues (P0-P2)

## Overview

Enchron QA Round 2 exposed 6 unresolved UI issues across all three page levels. The root cause is agent implementation drifting from HTML design specs, plus several visionOS platform API behaviors that differ from expectations. This plan fixes all issues using the HTML design files as the sole visual authority.

## Problem Framework

Agent implementations deviated from HTML mockups in layout, button ordering, and interaction patterns. Platform-specific issues (hover shape, ornament transition, window resize) compound the visual drift. A missing geometric constraint allows nonsensical mode switches (e.g., projecting flat video onto a sphere).

(see origin: docs/brainstorms/2026-04-05-known-issues-fix-requirements.md)

## Requirements Tracing

- R1. Player control bar pill layout matches `player.html` footer exactly: 5 core buttons (Menu, Rewind, Play/Pause, Forward, Settings) in pill-shaped glass container
- R2. Menu popup opens upward-left with: Subtitles, Audio Track, Playback Speed sub-menus
- R3. Settings popup opens upward-right with: Playback Mode, Environment sub-menus
- R4. Level 1 browse + Level 2 detail pages align with `variant-AB-combined.html`
- R5. Seek bar above control bar pill with time labels (left: current, right: remaining)
- R6. Hover effect shape matches button shape (circle → circle, rect → rect)
- R7. Use `.hoverEffect(.lift)` instead of `.hoverEffect(.highlight)` on visionOS
- R8. Controls show/hide is pure opacity fade (0.4s ease-in-out), no position shift
- R9. Ornament default transition must not override opacity-only intent
- R10. All `showControls` mutation sites wrapped in `withAnimation(.easeInOut(duration: 0.4))`
- R11. **CORRECTED**: Geometric constraint — panorama mode requires panoramic content; immersive mode is always available for all content types (see: docs/solutions/playback-mode-constraint-is-geometric-not-hierarchical-2026-04-05.md)
- R12. Mode menu shows only allowed modes; disable/hide panorama for non-panoramic content
- R13. `DecidePlaybackModeUseCase` manual override validates target mode against geometric constraint
- R14. Constraint logic lives in PlayerUI (Architecture Invariant: "PlayerUI owns mode decision")
- R15. Window resize triggers video canvas resize
- R16. GeometryReader wraps WindowVideoView, passes size to trigger `updateUIView`
- R17. MoltenVK 1x1 workaround preserved; legitimate resizes not filtered
- R18. NLE timeline panel has glass background (rgba(14,14,14,0.85) + blur 40px)
- R19. NLE buttons contained within panel bounds (clipped)
- R20. NLE drag: ruler draggable, track area draggable, playhead fixed at center
- R21. All player page buttons must be interactive (clickable, focusable, correct action)
- R22. Detail page button interactivity audited; non-functional buttons explained

## Scope Boundaries

- No architecture refactoring; fixes stay within existing module boundaries
- No new Domain layer entities
- No PlaybackCore internal logic changes
- No immersive scene rendering changes
- Level 1/2 alignment (R4): if >10 files affected, flag for separate PR
- NLE pinch-to-zoom: defer if implementation complexity is high

## Context & Research

### Relevant Code and Patterns

- `PlayerControlsView.swift` — 3-tier layout (info→seek→pill), `.hoverEffect(.highlight)`, `ForEach(PlaybackMode.allCases)`
- `MainView.swift:125-134` — ornament with `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.4))`
- `DecidePlaybackModeUseCase.swift:11-12` — manual override with zero validation
- `ProjectionType.swift` — `.isPanoramic`, `.isStereo3D` computed properties
- `WindowVideoView.swift` — UIViewRepresentable, no GeometryReader, `autoresizingMask` not sufficient
- `NLETimelineView.swift` — `.enchronGlassPanel()` applied, `.clipped()` present, height 160pt

### Institutional Knowledge

- **Geometric not hierarchical** (solutions): Flat→Immersive is LEGAL (virtual cinema = core differentiator). Only panorama mode requires panoramic projection.
- **HTML→SwiftUI pipeline** (solutions): 16 system components mandatory, 4 custom OK. Min button target 60x60pt. `.contentShape()` for hit area beyond visual size.
- **visionOS pitfalls** (solutions): `.sheet(item:)` manual nil clash, WindowGroup lifecycle race, system Menu discrete only, "A and B" partial implementation.
- **QA-Plan-First** (solutions): Code health ≠ user health. Four disease patterns: UseCase exists but UI never calls it; state emitted but UI branch missing.

### Technical Investigation Results

- `.hoverEffect(.highlight)` ignores `contentShape` on visionOS → use `.lift` (see: docs/reference/2026-04-05-known-issues-technical-investigation.md)
- `updateUIView` not called on window geometry change → GeometryReader needed
- Ornament may have built-in insertion transition → verify in simulator, apply `.transition(.identity)` if needed

## Key Technical Decisions

- **R11 corrected to geometric model**: The original "hierarchical" framing (2D→window only) was wrong. Immersive cinema mode works perfectly for all content types — it projects onto a virtual flat screen, not a sphere. Only panorama mode requires panoramic content. (see: docs/solutions/playback-mode-constraint-is-geometric-not-hierarchical-2026-04-05.md)
- **`.hoverEffect(.lift)` over `.highlight`**: `.highlight` on visionOS forces circular highlight regardless of `contentShape`. `.lift` respects custom shapes.
- **GeometryReader for canvas resize**: `updateUIView` doesn't trigger on window geometry changes. GeometryReader injects size as a dependency.
- **HTML as sole visual authority**: Agent must not invent layout. `player.html` and `variant-AB-combined.html` are the canonical references.
- **Button order follows HTML strictly**: 5 core buttons (Menu, Rewind, Play/Pause, Forward, Settings). NLE toggle functionality preserved via panel's own toggle mechanism or added to Settings menu — not as a standalone button in the pill unless HTML specifies it.

## Open Questions

### Resolved During Planning

- **Ornament transition override**: Current code at `MainView.swift:125-134` already applies `.transition(.opacity)` and `.animation(.easeInOut)`. Six `showControls` mutation sites already use `withAnimation`. The issue may be resolved by recent commits — needs simulator verification before additional code changes.
- **NLE toggle placement**: HTML `player.html` shows 5 buttons in control bar. NLE toggle is not a standalone button. Current implementation includes it as 6th button — it should be moved to Settings menu as "Timeline" toggle or triggered by the NLE panel's own interaction.

### Deferred to Implementation

- **R4 scope assessment**: Exact file count for Level 1/2 alignment unknown until implementation begins. Flag >10 files → separate PR.
- **mpv `vo-configured` event handling**: After GeometryReader integration, verify if mpv needs re-notification of output resolution change.
- **Seek bar interaction model**: HTML shows hover-reveal knob + click-to-seek. SwiftUI implementation may need `DragGesture` for smooth seeking — determine best approach during implementation.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not an implementation spec. The implementing agent should treat it as context, not code to reproduce.*

```
PlayerControlsView layout (matches player.html footer):

┌─────────────────────────────────────────────────────┐
│ [current_time]  ═══●═══════════════  [remaining]    │  ← Seek bar
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │ (Menu) (⏪10) ( ▶ Play ) (10⏩) (Settings) │    │  ← Pill glass container
│  └─────────────────────────────────────────────┘    │     border-radius: 9999px
└─────────────────────────────────────────────────────┘

Menu popup (upward-left):        Settings popup (upward-right):
┌──────────────┐                          ┌──────────────────┐
│ Subtitles  → │ ← sub-menu left         │ → Playback Mode  │
│ Audio      → │                          │ → Environment    │
│ Speed      → │                          └──────────────────┘
└──────────────┘

Mode constraint (geometric):
  ProjectionType → allowedModes
  flat/stereo    → [window, immersive]     ← immersive = virtual cinema, always OK
  panoramic      → [window, immersive, panorama]
```

## Implementation Units

### Phase 1: P0 — Player Page (Level 3) Layout Alignment

- [x] **Unit 1: Restructure PlayerControlsView layout to match player.html**

**Goal:** Rewrite the control bar to match the HTML footer: seek bar on top, pill-shaped button bar below with 5 buttons in correct order and sizes.

**Requirements:** R1, R5, R21

**Dependencies:** None

**Files:**
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlSurface.swift` (if button components extracted here)
- Reference: `docs/designs/file-browser-redesign-2026-04-05/player.html`

**Approach:**
- Replace 3-tier layout (info→seek→pill) with 2-tier: seek bar (top) → control pill (bottom)
- Remove info bar from controls ornament (info display is a separate concern, not part of the HTML footer)
- Control pill: HStack with gap 8pt, padding 24pt horizontal × 12pt vertical
- Control pill shape: Capsule (border-radius 9999px) with `.glassBackgroundEffect()` or `.enchronGlassControl()`
- Button order: Menu (48pt), Rewind 10s (48pt), Play/Pause (64pt with gradient), Forward 10s (48pt), Settings (48pt)
- Play/Pause larger with gradient background: linear-gradient 135deg from #c6c6c7 to #909191
- All buttons circular (`.clipShape(.circle)`, `.contentShape(.circle)`)
- Remove NLE toggle from main bar; preserve functionality via Settings menu or panel toggle
- Seek bar: HStack of time label (left, 11pt), progress track (flex, 4pt height, 6pt on hover), time label (right, 11pt)
- Seek bar gap from control pill: 20pt (gap-5 from HTML)
- Overall container: VStack(spacing: 20) wrapping seek + pill

**Patterns to Follow:**
- Current `.enchronGlassControl()` material for the pill
- Current `DesignTokens` color/spacing system
- HTML uses `tabular-nums` for time labels → use `.monospacedDigit()` in SwiftUI

**Test Scenarios:**
- Normal path: Controls display with correct 5-button order and seek bar above pill
- Normal path: Play/Pause toggles between play and pause icons
- Normal path: Rewind/Forward buttons trigger 10s seek
- Boundary: Seek bar progress at 0% and 100% renders correctly
- Integration: All 5 buttons trigger their correct action (menu opens, seek, play/pause)

**Verification:**
- Simulator screenshot matches player.html footer layout
- All 5 buttons are tappable and respond correctly
- Seek bar updates with playback progress

---

- [x] **Unit 2: Implement Menu and Settings popup menus**

**Goal:** Add left-expanding Menu popup and right-expanding Settings popup matching HTML design.

**Requirements:** R2, R3, R12 (mode menu filtered by constraint)

**Dependencies:** Unit 1 (button layout), Unit 6 (mode constraint for Settings > Playback Mode)

**Files:**
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- Reference: `docs/designs/file-browser-redesign-2026-04-05/player.html`

**Approach:**
- **Menu popup** (left button): Opens upward from button. Contains 3 items:
  - Subtitles → sub-menu (list of available subtitle tracks)
  - Audio Track → sub-menu (list of available audio tracks)
  - Playback Speed → scrollable sub-menu (0.25x to 5x, current marked with checkmark)
- **Settings popup** (right button): Opens upward from button. Contains 2 items:
  - Playback Mode → sub-menu (filtered by geometric constraint — Unit 7)
  - Environment → scrollable sub-menu (environment list with thumbnails)
- Popup container: 20pt border-radius, glass panel background (rgba(28,27,27,0.65) + blur 50px), 8pt padding, 2pt item gap
- Item styling: 16pt horizontal padding, 10pt vertical padding, 12pt font, 10pt border-radius
- Use SwiftUI `Menu` or custom popover for sub-menu cascading behavior
- visionOS pitfall: `Menu { Picker {} }` doesn't support `Slider` — all items must be discrete (per solutions docs)

**Patterns to Follow:**
- HTML popup animation: fade in 0.25s with translateY(8px) spring
- HTML sub-menu animation: fade in 0.2s with translateX(4px) spring
- Current mode menu logic at `PlayerControlsView.swift:265-401`

**Test Scenarios:**
- Normal path: Tapping Menu button opens popup with 3 items
- Normal path: Tapping Settings button opens popup with 2 items
- Normal path: Selecting subtitle track applies it
- Normal path: Selecting playback speed applies it
- Boundary: No subtitle tracks available → "None" or empty state
- Integration: Playback Mode sub-menu shows only allowed modes (requires Unit 7)

**Verification:**
- Both popups open in correct direction (Menu left, Settings right)
- Sub-menus cascade correctly
- Active items show checkmark
- Popup dismisses on outside tap

---

- [x] **Unit 3: Button interactivity audit (Level 3)**

**Goal:** Verify and fix all player page buttons to be interactive — clickable, focusable, triggering correct actions.

**Requirements:** R21

**Dependencies:** Unit 1, Unit 2

**Files:**
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- Modify: `XrPlayer/MainView.swift` (if hit testing or layer order blocks interaction)

**Approach:**
- After Unit 1 & 2 restructure, test every button in simulator
- Check for `.allowsHitTesting(false)` on parent views that might block interaction
- Check for overlapping views (z-order) that eat gestures
- Check state bindings — buttons must be connected to actual actions
- Use `mcp__XcodeBuildMCP__snapshot_ui` to inspect view hierarchy and hit test targets

**Test Scenarios:**
- Normal path: Each of 5 control buttons responds to tap
- Normal path: Seek bar responds to drag gesture
- Error path: Buttons disabled during immersive space transition show disabled state

**Verification:**
- Every button on the player page triggers its intended action in simulator
- No dead buttons or gesture-swallowing overlaps

---

### Phase 2: P1 — Interaction Fixes

- [ ] **Unit 4: Replace `.hoverEffect(.highlight)` with `.hoverEffect(.lift)`**

**Goal:** Fix hover effect shape to match button shape on visionOS.

**Requirements:** R6, R7

**Dependencies:** None (can be done independently)

**Files:**
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift` — all `.hoverEffect(.highlight)` occurrences
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlSurface.swift` — `.hoverEffect(.highlight)` at line ~47
- Modify: `XrPlayer/PlayerUI/Views/NLETimelineView.swift` — `.hoverEffect(.highlight)` at lines ~119, ~135
- Modify: `XrPlayer/SpatialScene/Views/SceneSelectorView.swift` — if `.hoverEffect(.highlight)` present

**Approach:**
- Global search for `.hoverEffect(.highlight)` across all Swift files
- Replace each with `.hoverEffect(.lift)`
- Verify each button retains its `.contentShape()` (circle for circular buttons, roundedRectangle for rect buttons)
- `.hoverEffect(.lift)` respects `contentShape` and produces correct 3D lift effect matching the shape

**Patterns to Follow:**
- Existing `.contentShape(.circle)` on circular buttons
- Existing `.contentShape(.rect)` on rectangular buttons

**Test Scenarios:**
- Normal path: Circular button shows circular hover lift effect
- Normal path: Rectangular button shows rectangular hover lift effect
- Boundary: Button with no explicit contentShape still shows reasonable hover

**Verification:**
- visionOS simulator or device shows hover shape matching button visual shape
- No circular hover on rectangular buttons

---

- [ ] **Unit 5: Fix controls show/hide to pure opacity fade**

**Goal:** Eliminate position shift animation on controls appear/disappear; ensure pure opacity 0.4s ease-in-out.

**Requirements:** R8, R9, R10

**Dependencies:** Unit 1 (controls layout must be stable)

**Files:**
- Modify: `XrPlayer/MainView.swift` — ornament definition (lines 125-134), all `showControls` mutation sites
- Reference: `docs/reference/2026-04-05-known-issues-technical-investigation.md`

**Approach:**
1. First verify in simulator: does the position shift still exist after recent commits (f234be8)?
2. If position shift persists:
   - The ornament container itself may have a built-in insertion transition
   - Try wrapping ornament content in a container with `.transition(.identity)` at the ornament level to suppress default transition
   - Ensure `.transition(.opacity)` is on the actual content, not fighting with ornament's own animation
3. Audit all `showControls` mutation sites:
   - `MainView.swift:154` — already `withAnimation`
   - `MainView.swift:157` — already `withAnimation`
   - `MainView.swift:172` — already `withAnimation`
   - `MainView.swift:206` — already `withAnimation`
   - `MainView.swift:211` — already `withAnimation`
   - `MainView.swift:223` — **NOT wrapped** in `withAnimation` — must fix
   - `MainView.swift:291` — already `withAnimation`
4. Ensure `withAnimation` uses `.easeInOut(duration: 0.4)` consistently (not default spring)

**Patterns to Follow:**
- Current `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.4))` pattern
- HTML reference: `transition: opacity 0.4s`

**Test Scenarios:**
- Normal path: Controls fade in smoothly with no position shift
- Normal path: Controls fade out smoothly with no position shift
- Boundary: Rapid show/hide toggle doesn't cause animation artifacts
- Integration: Auto-hide timer (8s) triggers smooth fade-out

**Verification:**
- Simulator recording shows pure opacity change, zero position/scale movement
- Consistent 0.4s duration across all show/hide triggers

---

- [ ] **Unit 6: Implement playback mode geometric constraint**

**Goal:** Prevent panorama mode for non-panoramic content. Allow immersive mode for all content.

**Requirements:** R11 (corrected), R12, R13, R14

**Dependencies:** None (logic is independent, but Unit 2's Settings > Playback Mode sub-menu will consume this)

**Files:**
- Modify: `XrPlayer/PlayerUI/UseCases/DecidePlaybackModeUseCase.swift` — add validation to manual override
- Modify: `XrPlayer/PlayerUI/Views/PlayerControlsView.swift` — filter mode menu
- Modify: `XrPlayer/PlayerUI/Domain/ValueObjects/PlaybackMode.swift` — add `allowedModes(for:)` static method
- Reference: `XrPlayer/PlaybackCore/Domain/ValueObjects/ProjectionType.swift` — `isPanoramic` property

**Approach:**
- Add `PlaybackMode.allowedModes(for projectionType: ProjectionType) -> Set<PlaybackMode>` as a static method on `PlaybackMode`:
  - If `projectionType.isPanoramic` → `[.window, .immersive, .panorama]`
  - Otherwise → `[.window, .immersive]`
- In `DecidePlaybackModeUseCase.decideMode()` (line 11-12): validate `manualOverride` against `allowedModes(for:)`. If override not in allowed set, clamp to nearest valid mode (`.window`)
- In `PlayerControlsView` mode menu: replace `ForEach(PlaybackMode.allCases)` with `ForEach(allowedModes)`. Pass current `projectionType` from `WindowVideoViewModel.currentMediaProfile.projectionType`
- This keeps all constraint logic in PlayerUI (Architecture Invariant)

**Patterns to Follow:**
- Current `ProjectionType.isPanoramic` computed property
- Current `DecidePlaybackModeUseCase` decision flow
- Architecture Invariant: "PlayerUI owns mode decision"

**Test Scenarios:**
- Normal path: Flat video shows Window and Immersive options only; Panorama hidden/disabled
- Normal path: Panoramic video shows all 3 options
- Normal path: Stereo 3D video shows Window and Immersive options only
- Error path: Manual override to `.panorama` for flat video → clamped to `.window`
- Integration: Auto-route still works correctly (panoramic → `.panorama`, flat → `.window`)
- Boundary: MediaProfile not yet detected → show all modes or default to window-only until detection completes

**Verification:**
- 2D video cannot switch to panorama mode
- Immersive (virtual cinema) mode works for all content types
- Panoramic video can access all 3 modes
- No regression on auto-route behavior (REG-109)

---

### Phase 3: P2 — Rendering & Timeline Fixes

- [ ] **Unit 7: Video canvas resize with GeometryReader**

**Goal:** Video canvas updates when visionOS window is resized.

**Requirements:** R15, R16, R17

**Dependencies:** None

**Files:**
- Modify: `XrPlayer/WindowVideoView.swift` — wrap in GeometryReader, pass size
- Modify: `XrPlayer/Shared/MPVNativeMetalLayerView.swift` — verify MoltenVK workaround doesn't filter legit resizes
- Modify: `XrPlayer/MainView.swift` — if WindowVideoView is embedded with constraints

**Approach:**
- Wrap `WindowVideoView` usage site in `GeometryReader`
- Pass `geometry.size` as a parameter to `WindowVideoView`
- In `updateUIView`, when size changes: update `metalLayer.frame`, call `metalLayer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)`
- MoltenVK 1x1 workaround at `MPVNativeMetalLayerView.swift:11-19`: keep it, but verify the `Int(newValue.width) > 1` check doesn't filter small but legitimate resize steps
- After resize, mpv may need notification — check if `vo-configured` event fires naturally or if manual property update is needed

**Patterns to Follow:**
- Current `autoresizingMask = [.flexibleWidth, .flexibleHeight]` pattern
- Current `layoutSubviews()` Metal layer update logic

**Test Scenarios:**
- Normal path: Dragging window edge resizes video canvas proportionally
- Normal path: Video aspect ratio maintained during resize
- Boundary: Very small window size doesn't crash (MoltenVK workaround)
- Boundary: Very large window size renders correctly
- Integration: Resize during active playback doesn't cause frame drops or artifacts

**Verification:**
- Video fills resized window without black bars (maintaining aspect ratio)
- No crashes or visual artifacts during resize

---

- [ ] **Unit 8: NLE timeline glass background and containment**

**Goal:** Fix NLE timeline panel appearance and button overflow.

**Requirements:** R18, R19, R20

**Dependencies:** None

**Files:**
- Modify: `XrPlayer/PlayerUI/Views/NLETimelineView.swift`
- Modify: `XrPlayer/PlayerUI/Views/TimelineRulerView.swift` — drag logic
- Modify: `XrPlayer/PlayerUI/Components/ThumbStripView.swift` — if overflow here
- Reference: `docs/designs/file-browser-redesign-2026-04-05/player.html` `.timeline-panel`

**Approach:**
- **Glass background**: Verify `.enchronGlassPanel()` matches HTML spec (rgba(14,14,14,0.85) + blur 40px). If not, adjust the glass modifier or apply custom background + `.blur()`.
- **Button containment**: The `.clipped()` modifier is already present (line 54). If buttons still overflow, check if `.clipped()` is applied in correct order (after frame, before padding). May need `RoundedRectangle` clip shape with correct insets.
- **Drag logic**: Ruler area should respond to horizontal drag. Playhead stays fixed at center, content scrolls. Verify `DragGesture` is on correct view and updates position correctly.
- Per HTML: timeline panel border-radius matches `--radius-card` (20px)

**Patterns to Follow:**
- Current `.enchronGlassPanel()` + `.clipped()` pattern
- HTML `.timeline-panel` styling

**Test Scenarios:**
- Normal path: NLE panel has visible glass background matching design
- Normal path: All buttons contained within panel bounds
- Normal path: Horizontal drag on ruler scrolls timeline content
- Boundary: Very short video → minimal timeline content, no overflow
- Boundary: Very long video → timeline scrolls smoothly without jank

**Verification:**
- Visual glass effect visible on NLE panel
- No buttons or UI elements overflowing panel edges
- Drag gesture works on ruler and track areas

---

### Phase 4: P0 — Browse & Detail Pages (Level 1 & 2) Alignment

- [ ] **Unit 9: Level 1 & 2 layout alignment audit and fix**

**Goal:** Align browsing page (Level 1) and detail page (Level 2) with `variant-AB-combined.html`.

**Requirements:** R4, R22

**Dependencies:** None (independent from player page fixes)

**Files:**
- Modify: `XrPlayer/FileBrowsing/Views/FileBrowserView.swift` — card grid, navigation
- Modify: `XrPlayer/FileBrowsing/Views/VideoCardView.swift` — card styling
- Modify: `XrPlayer/PlayerUI/Views/VideoDetailView.swift` — detail page layout
- Modify: `XrPlayer/MainView.swift` — navigation structure, ornament
- Reference: `docs/designs/file-browser-redesign-2026-04-05/variant-AB-combined.html`

**Approach:**
- **Scope assessment first**: Before making changes, compare current UI (simulator screenshot) with HTML design. List specific deviations.
- **If >10 files need changes → flag for separate PR** (per scope boundary)
- **Level 1 (browsing)**:
  - Card grid: 3 columns, 20pt gap, 16:9 aspect ratio cards
  - Content padding: 28pt horizontal
  - Navigation: vertical sidebar icons (72pt width)
  - Data source sidebar: 210pt width
- **Level 2 (detail page)**:
  - Two-column grid: 3fr + 2fr
  - Max width: min(92vw, 1100px), max height: min(85vh, 700px)
  - Left: video preview. Right: metadata panel with glass sub-panels
  - Title: 24pt font-extrabold. Metadata: grid-cols-2, label 10pt uppercase, value 16pt bold
  - Close button: 36x36pt, top-right corner
- **Button interactivity audit (R22)**: Test each button on detail page. Document which are functional vs non-functional and why.

**Patterns to Follow:**
- HTML design token system (spacing, colors, radii)
- Current `DesignTokens` Swift constants
- `.glassBackgroundEffect()` for panels

**Test Scenarios:**
- Normal path: Card grid displays 3 columns with correct spacing
- Normal path: Detail page opens with two-column layout
- Normal path: Detail page metadata displays correctly
- Normal path: Close button dismisses detail view
- Boundary: Single file → grid shows 1 card correctly
- Integration: Tapping card opens detail page with correct file's metadata

**Verification:**
- Simulator screenshots of browse and detail pages match HTML design layouts
- All expected buttons are interactive
- Non-functional buttons documented with reasons

---

## Dependency Graph

```
Unit 1 (Controls Layout) ──→ Unit 2 (Menus) ──→ Unit 3 (Interactivity Audit)
                                    ↑
Unit 6 (Mode Constraint) ──────────┘

Unit 4 (Hover Fix)         — independent
Unit 5 (Animation Fix)     — depends on Unit 1
Unit 7 (Canvas Resize)     — independent
Unit 8 (NLE Timeline)      — independent
Unit 9 (L1/L2 Alignment)   — independent
```

## System-Wide Impact

- **Controls ornament**: Restructuring ornament content (Unit 1) affects `MainView.swift` ornament block. Ensure ornament attachment anchor and alignment remain correct.
- **Mode transition**: Adding geometric constraint (Unit 6) affects `DecidePlaybackModeUseCase`, `PlayerControlsView`, and indirectly `AppModel.updatePlaybackMode`. Verify `MainView.onChange(of: playbackMode)` still handles transitions correctly.
- **WindowVideoView resize**: Adding GeometryReader (Unit 7) changes the view hierarchy around the video layer. Ensure no layout regressions for the main video display.
- **Regression touchpoints**: REG-109 (playback mode auto-route) directly affected by Unit 6.

## Risk & Dependencies

| Risk | Mitigation |
|------|------------|
| Ornament built-in transition may resist override | Test in simulator first; if `.transition(.identity)` fails, try content wrapper approach |
| GeometryReader may cause layout shifts in video area | Bind to `@State` size and only update when delta > threshold |
| Mode constraint may break existing auto-route flow | Add unit test verifying auto-route still works for all ProjectionType cases |
| Level 1/2 scope creep (>10 files) | Scope assessment first in Unit 9; flag for separate PR if threshold exceeded |
| NLE drag logic complexity | If ruler drag implementation is complex, focus on glass background and containment first (R18, R19), defer R20 drag refinement |

## Sources & References

- **Origin**: [docs/brainstorms/2026-04-05-known-issues-fix-requirements.md](docs/brainstorms/2026-04-05-known-issues-fix-requirements.md)
- **Handoff**: [docs/plans/active/2026-04-05-known-issues-handoff.md](docs/plans/active/2026-04-05-known-issues-handoff.md)
- **Technical investigation**: [docs/reference/2026-04-05-known-issues-technical-investigation.md](docs/reference/2026-04-05-known-issues-technical-investigation.md)
- **Mode hierarchy investigation**: [docs/reference/2026-04-05-playback-mode-hierarchy-investigation.md](docs/reference/2026-04-05-playback-mode-hierarchy-investigation.md)
- **Geometric constraint solution**: [docs/solutions/playback-mode-constraint-is-geometric-not-hierarchical-2026-04-05.md](docs/solutions/playback-mode-constraint-is-geometric-not-hierarchical-2026-04-05.md)
- **HTML design (player)**: [docs/designs/file-browser-redesign-2026-04-05/player.html](docs/designs/file-browser-redesign-2026-04-05/player.html)
- **HTML design (browse/detail)**: [docs/designs/file-browser-redesign-2026-04-05/variant-AB-combined.html](docs/designs/file-browser-redesign-2026-04-05/variant-AB-combined.html)
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Eng Review**: [docs/plans/active/2026-04-05-arch.md](docs/plans/active/2026-04-05-arch.md)

## ENG REVIEW AMENDMENTS (2026-04-05)

> Applied by /plan-eng-review. These amendments override the original unit descriptions where they conflict.

### Unit 1: Keep info bar + NLE toggle

- **Do NOT remove** `PlayerInfoBarView()` from `PlayerControlsView`. Instead, move it to a separate overlay in MainView's video ZStack (top-leading alignment), fading with `.transition(.opacity)` matched to controls animation. This matches HTML's separate top header design.
- **Keep** `NLETimelineToggleButton` in the pill as 6th button. HTML 5-button spec is a design reference; NLE is a core feature needing one-tap access.
- Revised pill: Menu, Rewind 10s, Play/Pause, Forward 10s, NLE Toggle, Settings

### Unit 2: Retain all existing menu items

- **Do NOT strip** Projection, Playlist, Screen Position, Settings, or Debug from the right menu.
- Apply geometric constraint filtering to Mode section (per Unit 6).
- Visual grouping may follow HTML styling, but content stays complete.

### Unit 4: Expanded file list (10 files, 15 occurrences)

Original list (4 files) + 6 missing files:
- `XrPlayer/PlayerUI/Views/PlayerInfoBarView.swift` (:20)
- `XrPlayer/FileBrowsing/Views/BreadcrumbView.swift` (:35)
- `XrPlayer/FileBrowsing/Views/FilterPillsView.swift` (:31)
- `XrPlayer/PlayerUI/Views/ScreenPositionControlView.swift` (:28)
- `XrPlayer/PlayerUI/Views/PlaylistView.swift` (:28, :80)
- `XrPlayer/App/Navigation/NavigationOrnament.swift` (:33, :57)

### Unit 5: Fix all showControls sites + close button

**MainView (7 sites):**
- Line 223: **ADD** `withAnimation(.easeInOut(duration: 0.4))` wrapper (currently bare assignment)
- Lines 154, 157, 172, 206, 211: **CHANGE** bare `withAnimation {}` to `withAnimation(.easeInOut(duration: 0.4)) {}`
- Lines 290-291: **CHANGE** bare `withAnimation {}` to `withAnimation(.easeInOut(duration: 0.4)) {}`

**Other files (audit, most intentional):**
- `XrPlayerApp.swift:111` — initial state setup, no animation needed. Leave as-is.
- `XrPlayerApp.swift:253` — cleanup/dismissal, no animation needed. Leave as-is.
- `PlayerControlsView.swift:516` (registerInteraction) — wrap in `withAnimation(.easeInOut(duration: 0.4))`.
- `PlayerControlsView.swift:529` (applySmokePanelRequestIfNeeded) — debug/setup path, leave as-is.
- `AppModel.swift:128` (startPlayback) — wrap in `withAnimation(.easeInOut(duration: 0.4))`.

**Close button (MainView:95-98):**
- Change `.transition(.asymmetric(...scale...offset...))` to `.transition(.opacity)`.

**Info bar overlay:**
- New info bar overlay (from Unit 1 amendment) gets `.transition(.opacity)`.

### Unit 6: Profile-pending safe default + dependency fix

- **Move `allowedModes(for:)` from `PlaybackMode` (Domain) to `DecidePlaybackModeUseCase` (UseCase).** PlayerUI/Domain does NOT import PlaybackCoreDomain. The UseCase layer already has this dependency.
- When `projectionType` is not yet detected (default/nil): `allowedModes` returns `[.window, .immersive]`.
- Add test case to TestPlan SC-3.
- **PiP button**: Explicitly deferred. Not applicable on visionOS. Annotated in requirements R1.

### Unit 7: Verify-first approach + MTKView path

- `setNeedsLayout()` already in `updateUIView` (commit f234be8). **Build and test in simulator first.**
- Add GeometryReader ONLY if `setNeedsLayout()` proves insufficient.
- If needed, use `onChange(of: geometry.size)` with delta threshold to prevent relayout spam.
- **MTKView fallback**: `updateUIView` only handles native GPU path. If GeometryReader needed, also update `mtkView.drawableSize` for the MTKView case.

### Unit 1 addendum: Seek bar remaining time

- HTML right label shows remaining time (countdown). Current code shows total duration.
- Change to `PlaybackTimeFormatter.clock(duration - currentTime)` with minus prefix.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | -- | -- |
| Codex Review | `/codex:rescue` | Independent 2nd opinion | 0 | -- | -- |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR | 7 P1 issues found + amended. Adversarial: 14 findings, 6 conditions conceded and resolved. |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | -- | -- |

**ADVERSARIAL:** 14 findings (1 critical, 4 high, 6 medium, 3 low). All 6 blocking conditions resolved: R11 superseded, PiP deferred, allowedModes moved to UseCase, Unit 2 dependency fixed, TestPlan R1 updated to 6 buttons, MTKView path added.
**VERDICT:** ENG REVIEW + ADVERSARIAL CLEARED. Plan implementable with all amendments applied.
