# Investigation: Playback Mode Hierarchy Constraint — Code Path Analysis

Date: 2026-04-05

## Core Finding

**No hierarchy constraint exists.** All 3 playback modes are always available to the user regardless of video content type. The auto-routing use case only sets defaults, but does not restrict manual overrides.

## Architecture Summary

```
PlaybackCore (provides facts)
  ProjectionType enum → flat | stereoscopicSBS | stereoscopicOU | panorama360 | panorama180 | fisheye
    .isPanoramic → panorama360, panorama180, fisheye
    .isStereo3D → stereoscopicSBS, stereoscopicOU
  MediaProfile struct → projectionType + hdrType + resolution + frameRate + codec + duration
  Exposure: PlaybackControlling.onMediaProfileDetected callback

PlayerUI (owns mode decision)
  PlaybackMode enum → window | immersive | panorama
  DecidePlaybackModeUseCase → auto-routes based on isPanoramic + isEnvironmentActive, accepts manual override unconditionally
  PlayerControlsView → ForEach(PlaybackMode.allCases) — always shows all 3 buttons

App (coordinates transitions)
  AppModel.playbackMode — single source of truth
  MainView.onChange(of: playbackMode) — opens/closes immersive space
  SceneSelectorView — shows 3 cinema environments, no filtering
```

## Key Files & Locations

| Component | File | Key Lines |
|-----------|------|-----------|
| ProjectionType | PlaybackCore/Domain/ValueObjects/ProjectionType.swift | 4-35 |
| MediaProfile | PlaybackCore/Domain/ValueObjects/MediaProfile.swift | 4-37 |
| MediaProfileDetecting | PlaybackCore/Domain/Ports/MediaProfileDetection.swift | 3-5 |
| ProjectionDetection (internal) | PlaybackCore/Adapters/MPV/ProjectionDetection.swift | 28-70 |
| PlaybackControlling | PlaybackCore/Domain/Ports/PlaybackControlling.swift | onMediaProfileDetected callback |
| PlaybackMode enum | PlayerUI/Domain/ValueObjects/PlaybackMode.swift | 1-8 |
| DecidePlaybackModeUseCase | PlayerUI/UseCases/DecidePlaybackModeUseCase.swift | 1-25 |
| PlayerControlsView | Views/PlayerControlsView.swift | 269-284 (mode menu), 471-475 (switchPlaybackMode) |
| AppModel | AppModel.swift | 29 (playbackMode), 83-85 (updatePlaybackMode), 95-114 (autoRoutePlaybackMode) |
| MainView | MainView.swift | 227-257 (onChange mode → scene transition) |
| WindowVideoViewModel | WindowVideoViewModel.swift | currentMediaProfile, displayMediaProfile |
| PlaybackLaunchCoordinator | App/PlaybackLaunchCoordinator.swift | triggers autoRoutePlaybackMode via detected projection |

## The Gap

### Current Behavior
1. `DecidePlaybackModeUseCase.decideMode()` auto-routes: panoramic → `.panorama`, immersive active → `.immersive`, else → `.window`
2. Manual override (line 12): `if let override = manualOverride { return override }` — **no validation**
3. `PlayerControlsView` mode menu (line 270): `ForEach(PlaybackMode.allCases)` — **shows all modes always**
4. Buttons disabled only when: mode is current OR immersive space transitioning

### What Happens When User Upgrades 2D → Panorama
1. User taps "panorama" button for a flat 2D video
2. `switchPlaybackMode(to: .panorama)` → `appModel.updatePlaybackMode(.panorama)`
3. MainView detects mode change, opens immersive space
4. ImmersiveSpaceView renders PanoramaSphereEntity — projects flat video onto a sphere
5. Result: distorted/broken visual, confusing UX

## Hierarchy Model (from requirements)

```
Tier 0 (basic):    flat                    → [window] only
Tier 1 (stereo):   stereoscopicSBS/OU      → [window, immersive]
Tier 2 (panoramic): panorama360/180/fisheye → [window, immersive, panorama]
```

Rule: **Can downgrade freely, cannot upgrade beyond content's native tier.**

## Fix Points (in PlayerUI, respecting Architecture Invariants)

1. **Add `allowedModes(for:)` logic** — derive from ProjectionType which PlaybackMode values are valid
   - Best location: extend `DecidePlaybackModeUseCase` or create a new `PlaybackModeConstraint` value object
2. **Filter mode menu in PlayerControlsView** — replace `PlaybackMode.allCases` with filtered list; disable/hide unsupported modes
3. **Validate manual override in DecidePlaybackModeUseCase** — clamp to allowed modes instead of blindly accepting

## Regression Touchpoints

- REG-109: 播放模式自动路由 — directly affected
- REG (unnumbered): switchPlaybackMode() in PlayerControlsView — directly affected
- New regression item needed for hierarchy constraint
