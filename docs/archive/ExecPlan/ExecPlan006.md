# ExecPlan 006 — C4+C5: Screen Position Controls Integration + X-axis Rotation

> Created: 2026-04-02T09:00+08:00
> Branch: MinimaxTest
> Status: IN_PROGRESS

---

## Goal

Integrate ScreenPositionControlView into the player UI and add X-axis rotation control. Currently the view exists but is completely orphaned — not connected to AppModel, not accessible from PlayerControlsView, and missing rotation slider.

## Current State

**Domain (DONE):**
- `SavedScreenPosition` — has `distanceMeters`, `verticalOffsetMeters`, `viewAngleDegrees`
- `ScreenPositionStoring` — protocol with `savePosition(for:distanceMeters:verticalOffsetMeters:angleDegrees:)` and `loadPosition(for:)`
- `SwiftDataStore` — fully implements persistence to UserDefaults

**UI (ORPHANED):**
- `ScreenPositionControlView` — has distance + vertical offset sliders with @State, no persistence, no rotation

**Integration (MISSING):**
- AppModel has no screen position state or ScreenPositionStoring injection
- PlayerControlsView has no screen position button or panel
- XrPlayerApp doesn't wire SwiftDataStore for screen position

## Implementation Units

### Unit 1: AppModel — Add screen position state + persistence

**File:** `XrPlayer/AppModel.swift`
- Add properties: `screenDistance: Double`, `screenVerticalOffset: Double`, `screenViewAngle: Double`
- Add `screenPositionStore: ScreenPositionStoring?` injection
- Add `loadScreenPosition(for environmentID:)` and `saveScreenPosition(for environmentID:)` methods
- Default values: distance=8.0 (Comfort), verticalOffset=0.0, viewAngle=0.0

### Unit 2: ScreenPositionControlView — Bind to AppModel + Add rotation slider

**File:** `XrPlayer/PlayerUI/Views/ScreenPositionControlView.swift`
- Replace @State with @Environment(AppModel.self) bindings
- Add X-axis rotation slider: range -45° to +45° (practical range for comfortable viewing)
- Presets for rotation: Left (-30°), Center (0°), Right (+30°)
- Auto-save on value change (debounced or on dismiss)

### Unit 3: PlayerControlsView — Add screen position button + panel

**File:** `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
- Add screen position toggle button in secondaryControlRow (only visible in immersive mode)
- Use modal panel pattern (same as PlaybackMenuView/DebugOverlayView)
- Show ScreenPositionControlView as overlay panel

### Unit 4: XrPlayerApp — Wire persistence

**File:** `XrPlayer/XrPlayerApp.swift`
- Ensure SwiftDataStore is created and injected
- Pass ScreenPositionStoring to AppModel

## Design Decisions

- Screen position controls only appear in immersive mode (no use in window mode)
- Rotation range ±45° (not ±180°) — beyond ±45° is uncomfortable in VR
- Save per environmentID — different presets can have different positions
- Use "virtual-screen" as default environmentID until multi-environment support

## Files Modified

1. `XrPlayer/AppModel.swift`
2. `XrPlayer/PlayerUI/Views/ScreenPositionControlView.swift`
3. `XrPlayer/PlayerUI/Views/PlayerControlsView.swift`
4. `XrPlayer/XrPlayerApp.swift`

## Risk

Low — domain layer is complete, UI patterns are established. Pure integration work.
