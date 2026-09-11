# Seek stall on high-pixel-rate media, and playback menus moved to system popovers

Physical Vision Pro `REDACTED`, Xcode destination
`REDACTED`, test plan `InteractiveDeviceSession`.

## Seek took seconds on 8K60 and was instant on 720p24

`180_3D.mp4` is HEVC 8192x4096 at 59.94 fps with keyframes every five seconds.
`Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4` is 1280x720
at 24 fps with keyframes every second. Seeking the first reported
`Playback Error / The playback command could not be completed` and stalled for
seconds; seeking the second was immediate.

`control.seek.teardownStages` was added to the live debug recorder to attribute
the stall, because the seek path between `control.seek.started` and
`renderer.flushedForSeek` had no instrumentation and the event timestamps carry
only one-second resolution. It reports each teardown call in milliseconds.

On 8192x4096 60 fps, everything except one call is sub-millisecond:

```
stopDelivery 40.2   videoProviderCancel 0.0   audioProviderCancel 0.0
rendererFlush 2770.7   total 2811.0
rendererFlush 4692.6   total 4733.5
```

`AVSampleBufferVideoRenderer.flush(removingDisplayedImage:)` is the whole stall,
and its cost tracks how much the renderer is holding. A seek issued immediately
after another one, against an already-drained queue, flushed in 0.4 ms.

The lead the delivery loop is allowed to hold was
`opportunisticRendererMaximumLeadSeconds`, six seconds on visionOS. Six seconds
is 360 frames at 60 fps, and at 8192x4096 that is what took seconds to tear
down; at 1280x720 24 fps the same six seconds is 144 small frames and costs
nothing. Seconds do not describe the cost, so the ceiling is now a pixel budget,
`opportunisticRendererMaximumLeadPixels`, converted to seconds through the
stream's own pixel rate and clamped between
`opportunisticRendererMinimumLeadSeconds` and the platform ceiling. The budget is
six seconds of 4K30, so ordinary streams keep the full lead and only streams
expensive enough to stall a seek tighten. 8K60 lands on the 0.75-second floor.

After the change, three steady-state seeks on the same clip and the same device:

```
rendererFlush 239.3   total 286.2
rendererFlush 260.4   total 296.1
rendererFlush 244.4   total 285.6
```

The 720p24 clip is unaffected, as its lead is unchanged:

```
rendererFlush 32.9   total 80.5
rendererFlush 34.5   total 74.7
```

The five-second keyframe interval still means a seek decodes up to 300 frames
before the target frame is presentable, which is the source's shape rather than
the player's.

## The playback secondary menus are system popovers

The Video Format and Dock menus used to be views the app laid out inside the top
chrome and dressed itself. Two things followed from that and both were visible on
the device.

They had no surface. Their backing was a system `Material`, which blurs whatever
SwiftUI backdrop sits behind it, and these menus float over the playback video,
which is a RealityKit mesh rather than a SwiftUI layer. With nothing to blur they
resolved to bare text over the picture:
[menu-before-no-glass.png](menu-before-no-glass.png).

They were clipped. The Video Format panel is 458 points tall and the chrome above
it costs 88, so it needs 546. The playback window's minimum height is 513, which
left 425 and cut off the Stereo Layout row along with Cancel and Apply:
[video-format-clipped-at-minimum-window.png](video-format-clipped-at-minimum-window.png).
Reproduce with `setWindowSize width=912 height=513` in Portal, then open Video
Format.

Both are now presented with the system popover, anchored to the button that opens
them. A popover hosts an arbitrary view, so the two orthogonal option groups and
the Cancel and Apply pair survive intact, which a `Menu` cannot do: a menu is a
list of adaptive controls, and the 2026-08-21 identifier survey on this same build
recorded that a menu discards `accessibilityIdentifier` on inline `Picker` rows,
`Toggle` rows, and anything inside a `Section`.

The device confirms both properties a popover was chosen for. It presents as its
own scene sized to the panel, `Window (Main), {{0, 0}, {520.0, 458.5}}`, so the
playback window's size cannot clip it, and every identifier is present, from
`PlayerUI-VideoFormat-Projection-180` through `-cancel` and `-apply`. At the
912x513 minimum the whole panel renders outside the window's edges and Cancel is
hittable and dismisses it:
[menu-after-popover-minimum-window.png](menu-after-popover-minimum-window.png).
At the default size it sits beside the window as an ordinary attached panel:
[menu-after-popover-default-window.png](menu-after-popover-default-window.png).

The popover supplies the surface, the outside-tap dismissal and the sizing, so the
app-side glass, the interaction shield that used to absorb outside taps, the fixed
420-point chrome region and its hardcoded-visual allowance are all gone with it.

A `ScrollView` inside the app-drawn panel was tried first and reverted. It made the
content reachable but left the panel cut at the same place, and it cost
hittability: `PlayerUI-VideoFormat-cancel` reported "exists but is not currently
hittable" while the menu was open, so the menu could no longer be dismissed from
its own button.

The Dock menu's conversion is verified by build and by code path only. Its button
appears only when the source is not panoramic, and the clip on hand carried a 180
override, so the device session could not open it.
