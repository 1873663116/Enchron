# After state, four UI defects

Physical Vision Pro `REDACTED`, merged tree `1ec490ce`, same clip as the
before run. Compare against `REPRO.md`.

## Window bar gap, verified

Diagnostic string at `presentation=window;controls=hidden;chrome=off;lifecycle=Playing`.

```
before   Window (Main) {{0,0},{1280,720}}   Window {{0,0},{728,152}}   outer {{0,0},{1680,1404}}
after    Window (Main) {{0,0},{1280,720}}   (no 728x152 window)        outer {{0,0},{1680,1252}}
```

The reserved ornament window is gone while controls are hidden, and the outer window shrank by
exactly 152, which is `collapsedWindowControlsOrnamentHeight`. Screenshot `33a1ca0d-…png` shows the
window bar sitting against the video. With controls shown the 728x152 window returns, so the
ornament now exists only when the deck does.

## Metadata truncation, verified

Controls shown, same well at `{{264.0, 12.0}, {440.0, 72.0}}`.

```
before   'Flat · Mono' {{288.0, 62.5}, { 61.5, 13.5}}   technical {{498.0, 64.2}, {182.0, 10.0}}
after    'Flat · Mono' {{288.0, 62.5}, { 61.5, 13.5}}   technical {{401.0, 62.5}, {279.0, 13.5}}
```

The trailing label grew from 182 to 279 wide by starting 97 further left, into space the leading
label never used. Its height returned from 10.0 to 13.5, matching the leading label, so
`minimumScaleFactor` is no longer shrinking it. Its right edge stayed at 680, so right alignment
holds. Full string `3840×2160 · Dolby Vision Profile 5 · HEVC · 24 fps` renders without an ellipsis.

## Sidebar More button, geometry only

```
before   Button {{168.0, 20.0}, {36.0, 36.0}}  identifier 'FileBrowsing-MainWindow-sidebar'
after    Button {{144.0, 20.0}, {60.0, 60.0}}  identifier 'FileBrowsing-SourcesSidebar-sourceMore'
```

Target grew to 60, matching `FileBrowsing-FilesScreen-sidebarToggle`, and the element now carries
its own identifier instead of the container's.

Activation is not verified. XCUI reports `isHittable=False` for this button, and equally for
`FileBrowsing-FilesScreen-sidebarToggle`, `FileBrowsing-FilesScreen-sort` and
`FileBrowsing-Manage-button`, none of which these fixes touched. Content-area taps on the same
session succeed, so the session holds input ownership. Synthetic taps do not carry gaze plus pinch
semantics, so XCUI hittability cannot settle whether the wearer can now activate it.

## Hover overflow, not verified here

Gaze-driven. `Scripts/verification/check_hover_region_clipping.py` reports 0 confirmed violations on
the merged tree across 65 files and 90 controls, which is structural evidence only.

## Blackout regression, not run

`measure_controls_flash.py` aborted before its first toggle, `runError: open 180_3D failed`, so its
empty `toggleBlackouts` means nothing. Reading the script, it taps a clip by label and then
`PlayerUI-TopAction-resumePanorama`, so it measures the panorama control path. That is the path
commit `7fc50cf9` measured and `cb63b07e` moved into the immersive space. It is not the main-window
ornament path that changed here, so it is the wrong instrument for this change regardless of the
clip.
