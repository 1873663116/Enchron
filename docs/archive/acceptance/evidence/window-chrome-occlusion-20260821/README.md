# Window playback chrome was drawn behind the video mesh

## Symptom

Playing a title in Window presentation, the top row of playback chrome (Back, Dock,
Video Format, More) and the top and bottom edge scrims never appeared. The bottom
Player Controls ornament appeared normally, so the controls looked half-summoned.
The Accessibility hierarchy reported every top button present and correctly framed
at the same moment the pixels showed none of them.

## Mechanism

`PlaybackRealityPresenter.configure` gives the Window video entity
`ModelSortGroupComponent(group: .planarUIInline, order: 0)`. `planarUIInline` orders a
mesh against coincident SwiftUI layers by z rather than by the view tree, so a SwiftUI
overlay that sits at the same z as the mesh is not guaranteed to draw over it. The
Window RealityView uses `flatWindowDepth` of 0, which puts the mesh exactly on the
Window's SwiftUI plane, and `WindowPlaybackRootView` layered its chrome as plain
overlays with no forward offset. The mesh won every tie and covered the whole window.

Apple's `ModelSortGroup.PlanarUIPlacement` reference pairs `planarUIInline` with
`.offset(z: .ulpOfOne)` on the SwiftUI layer that must draw in front. That forward
step is what was missing.

`WindowPlaybackSurfaceGeometry.coincidentChromeDepth` now carries it, and both the
top chrome plane and the edge emphasis apply it.

## Evidence

Physical Vision Pro `REDACTED`, Xcode destination
`REDACTED`, test plan `InteractiveDeviceSession`, clip
`Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4` in Window
presentation, both frames captured with `showControls` true.

Before the fix, the video and bottom ornament appeared without the top row or edge
scrims. After the fix, Back, Dock, Video Format, More, and the edge scrims appeared.

Two screenshots of one paused frame, taken with chrome on and chrome off, differed
only in the ornament band before the fix. Neither the top chrome nor either edge
scrim contributed a single pixel, which is what ruled out a contrast or material
problem and pointed at draw order.

After the fix, a real tap on the Video Format gear opened the format editor, so the
restored chrome is reachable and not merely visible.

## Residual

The Video Format secondary panel reads as very translucent over bright video. It is
drawn, and its rows are addressable, but its contrast against a bright frame is worth
a separate look.
