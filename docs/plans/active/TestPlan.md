---
title: "TestPlan: Enchron UI/UX Redesign"
type: refactor
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-uiux-redesign-requirements.md
exec_plan: docs/plans/active/ExecPlan.md
---

# TestPlan: Enchron UI/UX Redesign

## Overview

Dual-track verification plan for the UI/UX redesign. Track 1: automated tests (compilation, unit, structural). Track 2: human verification (visual, interaction, end-to-end flows on visionOS Simulator/device).

The core insight from prior overnight: **code health ≠ user health** (97.75% vs 70.7%). This plan prioritizes E2E flow verification over unit test count.

## Regression Strategy

### Existing Test Baseline

- **14 test files** in `Tests/XrPlayerCoreTests/`
- **0 UI/View tests** — all existing tests cover Domain/UseCase/Core logic
- **Key test files:** CoreLogicTests, V04Tests, V03Tests, V02Tests, PlaybackModeRoutingTests, DetailedTimelineGeometryTests, PlaybackTimeFormatterTests, CinemaEnvironmentTests

### Regression Guarantee

All 248 existing tests MUST continue to pass after every implementation unit. Verification method:

```
xcodebuild test -scheme XrPlayer -destination 'platform=visionOS Simulator'
```

**Why existing tests are safe:** The redesign modifies View and ViewModel layers only. All existing tests cover Domain, UseCase, and Core layers which are untouched. Risk areas:
- `DetailedTimelineGeometryTests` — safe, geometry logic unchanged (NLE builds on top)
- `PlaybackModeRoutingTests` — safe, routing logic in PlayerUI/Domain unchanged
- `CinemaEnvironmentTests` — safe, domain model unchanged

### REGRESSION.md Cross-Reference

UI changes trigger these regression item groups (must be verified after relevant units):

| Regression Group | Triggered By Units | Items |
|---|---|---|
| REG-080~081 | Unit 12, 14-16 | Timeline, frame stepping |
| REG-082~089 | Unit 6-10, 12 | Detail view, progress, data sources |
| REG-090~096 | Unit 7, 11 | Data source config, cache, network |
| REG-100~107 | Unit 13 | Virtual screen, environment, immersive |
| REG-108~122 | Unit 12, 13 | Playback routing, immersive controls |

## Acceptance Criteria

### AC-A: Design Foundation (R1-R4)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-A1 | 9 Color Sets in Asset Catalog with correct hex values | Build + visual inspection in Xcode |
| AC-A2 | `Color.enchronSurface` etc. resolve at runtime | Unit test: color != nil |
| AC-A3 | DesignTokens.Radius.card == 20, .window == 40, .badge == 10 | Unit test |
| AC-A4 | 4 glass variant modifiers compile and render | Build + simulator visual check |
| AC-A5 | No hardcoded `.system(size:)` font in new code | Grep: `\.system\(size:` in modified files = 0 |
| AC-A6 | No hardcoded color hex in new code | Grep: `Color(red:` / `UIColor(` in modified View files = 0 |

### AC-B: Global Navigation (R5-R9a)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-B1 | Leading ornament visible on main window left edge | Simulator screenshot |
| AC-B2 | 3 navigation items (Browse/Recent/Settings) + Scene button | Visual inspection |
| AC-B3 | Active tab uses tertiary color, inactive uses onSurfaceVariant | Visual inspection |
| AC-B4 | Tab switching changes main content area | Simulator: tap each tab → verify content |
| AC-B5 | Scene button opens SceneSelectorView as .sheet | Simulator: tap → verify sheet |
| AC-B6 | Navigation state lives in AppModel (not @State in View) | Grep: `selectedTab` not in any View as @State |
| AC-B7 | AppTabView.swift deleted, no references remain | Grep: `AppTabView` = 0 |
| AC-B8 | Recent view shows playback history sorted by time | Simulator: play video → check Recent tab |
| AC-B9 | Recent view handles empty state with guidance text | Simulator: fresh install → check Recent tab |

### AC-C: File Browser (R10-R18)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-C1 | NavigationSplitView two-column layout renders | Simulator screenshot |
| AC-C2 | Sidebar shows Local + saved remote sources | Simulator: add SMB → verify sidebar |
| AC-C3 | Source selection changes content in detail area | Simulator: tap source → verify |
| AC-C4 | Storage bar shows used/total for local source | Simulator visual check |
| AC-C5 | Breadcrumb shows current path, segments tappable | Simulator: navigate folders → verify |
| AC-C6 | Filter pills (All/4K/HDR/Spatial) filter content grid | Simulator: tap filter → verify grid changes |
| AC-C7 | VideoCardView renders with thumbnail area + badges | Simulator screenshot |
| AC-C8 | Card hover lifts with parallax badges | Simulator: gaze at card → verify lift |
| AC-C9 | Card tap opens VideoDetailView as .sheet | Simulator: tap card → verify sheet |
| AC-C10 | Detail sheet left column: preview + env selector + play | Simulator visual check |
| AC-C11 | Detail sheet right column: metadata + settings pickers | Simulator visual check |
| AC-C12 | "Start Playback" triggers full launch flow | Simulator: tap play → video plays |
| AC-C13 | Sheet dismiss calls cancelPreparedPlayback | Simulator: open detail → swipe dismiss → verify no stale state |
| AC-C14 | Data source config sheet flow preserved | Simulator: add source → credentials → share select |

### AC-D: Player Controls (R19-R25)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-D1 | Control bar has pill/capsule glass shape | Simulator screenshot |
| AC-D2 | Button order: Menu \| Rew \| Play \| Fwd \| Settings | Visual inspection |
| AC-D3 | Left menu shows HDR/Subtitles/Audio/Speed | Simulator: tap menu → verify items |
| AC-D4 | Right menu shows Mode/Environment | Simulator: tap settings → verify items |
| AC-D5 | Seek Slider reflects and controls position | Simulator: drag slider → verify seek |
| AC-D6 | Auto-hide after 5 seconds of inactivity | Simulator: wait 5s → controls fade |
| AC-D7 | Controls reappear on interaction | Simulator: tap after hide → controls show |
| AC-D8 | Top info bar: back button + title + format metadata | Simulator visual check |
| AC-D9 | PlaybackMenuView.swift deleted | File does not exist |
| AC-D10 | ScreenPositionControlView restyled with design tokens | Visual inspection: glass + colors match system |
| AC-D11 | Companion window appears in immersive mode | Simulator: enter immersive → verify window |
| AC-D12 | Companion window dismissed on immersive exit | Simulator: exit immersive → verify dismissed |
| AC-D13 | Companion window shows same controls as window mode | Visual comparison |

### AC-E: NLE Timeline (R26-R31)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-E1 | Timeline panel expands/collapses with spring animation | Simulator: tap toggle → verify animation |
| AC-E2 | Ruler shows time ticks and labels | Simulator visual check |
| AC-E3 | Playhead fixed at center | Simulator visual check |
| AC-E4 | Drag gesture scrolls timeline | Simulator: drag → verify position change |
| AC-E5 | Pinch gesture zooms timeline | Simulator: pinch → verify zoom |
| AC-E6 | Frame step forward/backward buttons work | Simulator: tap → verify single frame advance |
| AC-E7 | Timeline geometry adapts to zoom level | Simulator: zoom → verify tick density changes |

### AC-F: Accessibility & Animation (R32-R39)

| ID | Criterion | Verification |
|----|-----------|-------------|
| AC-F1 | All interactive elements ≥ 60×60pt gaze target | Audit: measure or grep for .contentShape |
| AC-F2 | VoiceOver reads video card label correctly | VoiceOver test |
| AC-F3 | Timeline has custom accessibility actions | VoiceOver: verify Play/Pause/Frame Step actions |
| AC-F4 | Reduce Motion → no spring animations | Toggle Reduce Motion → verify |
| AC-F5 | Focus lands on title when detail sheet opens | VoiceOver: open sheet → verify focus |
| AC-F6 | Zero custom hover translateY effects | Grep: `translateY\|offset.*hover` in View files = 0 |
| AC-F7 | Zero custom scaleEffect press effects | Grep: `scaleEffect.*pressed\|scaleEffect.*isPressed` = 0 |
| AC-F8 | All panels use .sheet/.popover (no withAnimation opacity) | Grep verification |
| AC-F9 | Drag uses interactiveSpring, release uses spring | Code review of gesture handlers |

## End-to-End Test Scenarios

### E2E-1: Fresh Launch to Video Playback (Critical Path)

**Precondition:** Fresh app install, no saved data sources
**Steps:**
1. App launches → leading ornament visible with Browse active
2. Main content shows file browser with NavigationSplitView
3. Sidebar shows "Local Storage" only
4. Tap Local Storage → content grid shows local videos as cards
5. Tap a video card → detail sheet opens with preparing state
6. Sheet transitions to ready state with audio/subtitle pickers
7. Tap "Start Playback" → video plays in window mode
8. Player controls visible as bottom pill ornament
9. Controls auto-hide after 5 seconds
10. Tap to show controls → controls reappear

**Covers:** AC-B1, AC-B4, AC-C1, AC-C2, AC-C7, AC-C9, AC-C12, AC-D1, AC-D6, AC-D7

### E2E-2: Remote Data Source Browse & Play

**Precondition:** SMB server available on network
**Steps:**
1. From Browse tab, sidebar shows "+" or toolbar button for new source
2. Tap add → DataSourceConfigView sheet opens
3. Enter SMB credentials → advance to share selection → save
4. New source appears in sidebar
5. Tap new source → content grid populates with remote files
6. Breadcrumb shows source name → folder path
7. Navigate into subfolder → breadcrumb updates
8. Tap breadcrumb root → returns to source root
9. Tap video card → detail sheet → play → video plays

**Covers:** AC-C2, AC-C3, AC-C5, AC-C14, AC-C9, AC-C12

### E2E-3: Filter & Navigate File Browser

**Precondition:** Local storage has mix of 4K, HDR, and standard videos
**Steps:**
1. Browse tab active, content grid shows all videos
2. Tap "4K" filter pill → grid shows only 4K videos
3. Active pill shows tertiary color
4. Tap "All" → grid shows all videos again
5. Navigate into subfolder → breadcrumb shows path
6. Filter still applies within subfolder
7. Tap breadcrumb parent → returns to parent folder

**Covers:** AC-C5, AC-C6, AC-C7

### E2E-4: Navigation Tab Switching

**Precondition:** At least one video has been played
**Steps:**
1. Launch on Browse tab → file browser visible
2. Tap Recent in ornament → recent playback list visible
3. Recently played video shown with card
4. Tap Settings → settings list visible
5. Tap Browse → file browser visible again
6. Tap Scene button → SceneSelectorView opens as sheet
7. Select environment → sheet dismisses

**Covers:** AC-B1, AC-B2, AC-B3, AC-B4, AC-B5, AC-B8

### E2E-5: Playback Resume Flow

**Precondition:** Video has been partially watched (>5 seconds progress)
**Steps:**
1. Navigate to previously watched video
2. Tap video card → detail sheet opens
3. Resume prompt appears: "Resume from XX:XX" / "Start from beginning"
4. Tap "Resume" → playback starts from saved position
5. Play different video → tap same video again → resume prompt shown

**Covers:** AC-C12, AC-C13 (via prior dismiss)

### E2E-6: Player Controls — Menu System

**Precondition:** Video playing in window mode
**Steps:**
1. Controls visible → tap left Menu button
2. Menu popup shows: HDR toggle, Subtitles picker, Audio picker, Speed picker
3. Select subtitle track → subtitle appears
4. Dismiss menu → tap right Settings button
5. Settings menu shows: Playback Mode picker, Environment selector
6. Change mode to Immersive → companion window appears, main window enters immersive

**Covers:** AC-D2, AC-D3, AC-D4, AC-D11

### E2E-7: Immersive Mode Lifecycle

**Precondition:** Video playing in window mode
**Steps:**
1. Switch to immersive mode via settings menu
2. ImmersiveSpace opens → companion window appears with controls
3. Companion window controls are functional (play/pause, seek, menus)
4. Switch back to window mode via companion window settings menu
5. Companion window dismissed → ornament controls reappear
6. Stop playback → verify clean state

**Covers:** AC-D11, AC-D12, AC-D13, REG-100~107

### E2E-8: NLE Timeline Interaction

**Precondition:** Video playing
**Steps:**
1. Tap timeline toggle → panel expands with spring animation
2. Ruler shows time ticks corresponding to video duration
3. Playhead visible at center
4. Drag timeline → playback position changes
5. Release → spring settle animation
6. Pinch zoom → tick density changes
7. Tap frame step forward → advances one frame
8. Tap frame step backward → retreats one frame
9. Tap toggle → panel collapses

**Covers:** AC-E1 through AC-E7

### E2E-9: Accessibility Full Traversal

**Precondition:** VoiceOver enabled
**Steps:**
1. VoiceOver announces leading ornament buttons
2. Navigate through ornament → each tab announced
3. Move to file browser → sidebar announced, sources listed
4. Move to grid → cards announced with label "Video: name, duration, format"
5. Activate card → sheet opens, focus on title
6. Navigate through detail controls → all announced
7. Start playback → controls announced
8. Timeline accessible actions available
9. Reduce Motion toggled → spring animations disabled

**Covers:** AC-F1 through AC-F5

### E2E-10: Design Consistency Audit

**Precondition:** All units implemented
**Steps:**
1. Screenshot every primary screen state (browse, recent, settings, detail, playing, immersive, timeline)
2. Verify: no hardcoded colors (all from design tokens)
3. Verify: glass effects use 4 defined variants only
4. Verify: all text uses semantic font styles
5. Verify: card radius = 20, window radius = 40, badge radius = 10
6. Verify: active states use tertiary color
7. Verify: no custom hover/press/panel animations

**Covers:** AC-A1 through AC-A6, AC-F6 through AC-F9

## Structural Verification (Agent-Executable)

These checks can be automated without visionOS Simulator interaction:

### Build Verification
```
xcodebuild build -scheme XrPlayer -destination 'platform=visionOS Simulator'
```

### Existing Test Suite
```
xcodebuild test -scheme XrPlayer -destination 'platform=visionOS Simulator'
```

### Structural Greps

| Check | Command Pattern | Expected |
|-------|----------------|----------|
| No hardcoded font size | `grep -r '\.system(size:' XrPlayer/ --include='*.swift'` | 0 matches in new/modified files |
| No hardcoded color hex | `grep -r 'Color(red:\|UIColor(' XrPlayer/ --include='*.swift'` | 0 matches in View files |
| No AppTabView references | `grep -r 'AppTabView' XrPlayer/ --include='*.swift'` | 0 matches |
| PlaybackMenuView deleted | `find XrPlayer -name 'PlaybackMenuView.swift'` | 0 results |
| ScreenPositionControlView restyled | `grep -r 'enchronGlass' XrPlayer/PlayerUI/Views/ScreenPositionControlView.swift` | ≥1 match (uses design tokens) |
| Navigation state in AppModel | `grep -r 'selectedTab' XrPlayer/ --include='*.swift'` | Only in AppModel + Views reading it |
| Gaze targets | `grep -r 'contentShape' XrPlayer/ --include='*.swift'` | Present on small interactive elements |
| Accessibility labels | `grep -r 'accessibilityLabel' XrPlayer/ --include='*.swift'` | Present on cards + controls |
| System Menu usage | `grep -r 'Menu {' XrPlayer/PlayerUI/ --include='*.swift'` | Present in PlayerControlsView |

### Environment Injection Audit

Verify all new/modified Views receive required dependencies:

| View | Required Environment |
|------|---------------------|
| NavigationOrnament | AppModel |
| ContentGridView | FileBrowsingViewModel |
| VideoCardView | (parameters, no environment) |
| RecentlyPlayedView | ProgressStoring (injected) |
| PlayerInfoBarView | AppModel, WindowVideoViewModel |
| NLETimelineView | AppModel, WindowVideoViewModel |
| Companion WindowGroup | AppModel, WindowVideoViewModel, FileBrowsingViewModel, PlaybackLaunchCoordinator, PanoramaLayerBridge |

###断联检查 (Disconnection Check)

For each new View-ViewModel interaction:

| View | ViewModel Method | Verification |
|------|-----------------|-------------|
| RecentlyPlayedView | progressStore.loadRecentlyPlayed | Grep: method called in View or its ViewModel |
| FileBrowserSidebar | viewModel.connectToDataSource | Grep: called on source selection |
| ContentGridView | viewModel.files (filtered) | Grep: files property read in grid |
| FilterPillsView | viewModel.activeFilters | Grep: filter state read and applied |
| BreadcrumbView | viewModel.navigationPath | Grep: path segments populated |

## QA Flywheel Rules

From TestPlan: TESTING phase operates as a flywheel:
1. Run E2E scenarios → collect PASS/FAIL
2. FAIL → diagnose → fix → re-test specific scenario
3. All PASS → adversarial review → final PASS
4. `fix_max_retries: 6` — max 6 fix-retest cycles before BLOCKED

### QA Priority Order
1. E2E-1 (Critical path: launch → play) — must pass first
2. E2E-6, E2E-7 (Controls + immersive) — core experience
3. E2E-2, E2E-5 (Remote + resume) — data flow integrity
4. E2E-3, E2E-4 (Navigation) — UX completeness
5. E2E-8 (Timeline) — custom component quality
6. E2E-9 (Accessibility) — compliance
7. E2E-10 (Design audit) — visual consistency

### Human Verification Checklist Template

After each phase completion, generate human verification items in this format:

```
## Phase [X] Human Verification

- [ ] [AC-ID] Description — Verification method
- [ ] Screenshot: [screen state]
- [ ] Regression: [REG-xxx items to recheck]
```
