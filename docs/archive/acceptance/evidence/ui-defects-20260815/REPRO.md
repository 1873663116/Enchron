# Before state, three UI defects

Physical Vision Pro `59E3D57A-0288-53DC-9A7D-B657B6939558`, session `1DF8AB66-CB96-43B0-9182-5C3AA0F0E13E`,
build at `defaf387`, clip `Patterns_Of_Nature_DoVi_24_P5_UHD_HEVC-10mbps_DD+JOC-768kbps_iOS.mp4`.

## Window bar gap

Diagnostic string reports `presentation=window;controls=hidden;chrome=off;lifecycle=Playing`.
The Accessibility hierarchy at that moment still carries a separate window:

```
Window (Main), {{0.0, 0.0}, {1280.0, 720.0}}
Window,        {{0.0, 0.0}, {728.0, 152.0}}
```

728 is `DesignTokens.ControlBar.outerWidth`. 152 is `collapsedWindowControlsOrnamentHeight`
(`Apps/Enchron/MainView.swift`). The ornament occupies its full 152 pt with the deck hidden and no
chrome drawn, so the system window bar is pushed 152 pt below the video. `2d5704fe-…png` is the
matching pixel capture.

With controls shown the ornament measures the same 728×152, so the reservation is not slack the deck
needs; it is constant.

## Metadata truncation

Controls shown, media information well at `{{264.0, 12.0}, {440.0, 72.0}}`:

```
StaticText {{288.0, 62.5}, { 61.5, 13.5}}  'Flat · Mono'
StaticText {{498.0, 64.2}, {182.0, 10.0}}  '3840×2160 · Dolby Vision Profile 5 · HEVC · 24 fps'
```

Interior after `.padding(.horizontal, Spacing.xl)` spans x 288→680, 392 pt, split into two 184 pt
halves by the paired `.frame(maxWidth: .infinity)`. The leading label consumes 61.5 pt and leaves
about 122 pt unused. The trailing label is confined to its 184 pt half and its height has dropped to
10.0 pt against the leading label's 13.5 pt, so `.minimumScaleFactor(0.75)` has already scaled it to
75 percent to fit.

## Hover overflow

Not reproduced from this lane. The hover highlight is driven by gaze, and XCUIAutomation cannot
derive an activation point for it (see the skill's diagnostics reference). Evidence for this defect
is the wearer's photograph plus the structural audit.
