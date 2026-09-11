# Device acceptance, merged integration branch

Physical Vision Pro `REDACTED`, tree `027e8cd6`
(`fix/ui-defects-integration`), clip `180_3D.mp4` imported through the production
pipeline after `resetState`. Controller output under
`/Volumes/Cortisol/BuildArtifacts/acceptance-20260815/`.

## Top chrome holds position across the visibility change

Same session, `toggleControls` twice, hierarchy read after each.

```
shown    PlayerUI-window-top-overlay        {{24.0, 20.0}, {1310.0, 60.0}}
         PlayerUI-TopAction-dock            {{96.0, 20.0}, {60.0, 60.0}}
         PlayerUI-TopAction-videoFormat     {{1202.0, 20.0}, {60.0, 60.0}}
         PlayerUI-TopAction-more            {{1274.0, 20.0}, {60.0, 60.0}}
hidden   PlayerUI-window-top-overlay        {{24.0, 20.0}, {1310.0, 60.0}}
         PlayerUI-TopAction-dock            {{96.0, 20.0}, {60.0, 60.0}}
         PlayerUI-TopAction-videoFormat     {{1202.0, 20.0}, {60.0, 60.0}}
         PlayerUI-TopAction-more            {{1274.0, 20.0}, {60.0, 60.0}}
```

The subtree stays resident with identical frames, so the animated transaction has
no subtree insertion and no horizontal layout endpoint left to interpolate.

`.accessibilityHidden(!showsWindowChrome)` does not remove these elements from the
XCUI hierarchy; hidden chrome is still listed. Input is still refused, because
`.allowsHitTesting(showsWindowChrome)` carries that.

## Ornament reservation stays collapsed

Portal, controls hidden, outer window `{{0,0},{1680,1252}}` and no `728x152` window.
Showing controls brings the `728x152` ornament window back.

## Metadata row renders in full

```
'Flat · Mono'                            {{288.0, 62.5}, { 61.5, 13.5}}
'8192×4096 · SDR · HEVC · 59.9401 fps'   {{461.0, 62.5}, {219.0, 13.5}}
```

Right edge 680, full 13.5 height, no ellipsis.

## Local folder counts survive the optional-count change

Media Library `Samples` grid: CameraOriginals `3 items`, DynamicRange `3 items`,
Professional `1 items`, Spatial `3 items`.

## Portal to Panorama, local 180 side-by-side source

Applying Projection 180° with Side-by-Side moved the session to
`presentation=portal;actualImmersiveMode=portal;corePresentationPhase=settled`.
Tapping `PlayerUI-TopAction-resumePanorama` then produced

```
presentation=portal;transition=panorama;immersiveSpaceResidency=open
corePresentationPhase=surfaceAttached;error=none
lastExecutionResolution=succeeded-presentationCommitted(portal)
```

and the control plane subsequently left the hierarchy, which is the settled
immersive signature. PlaybackCore's live channel for session
`322AEE5D-6E66-4C5C-B85A-8D0920186654` records `actualImmersiveViewingMode=progressive`
followed by `presentation.detached`, `session.cleanup` and
`operation.close.completed`, all `succeeded`. No `videoRenderer.firstFrameTimedOut`
appears anywhere in that event stream.

## Not covered here

Remote-source Portal to Panorama, and remote folder cards, need a WebDAV source
selected in the sidebar. Every sidebar and toolbar control reports
`isHittable=False` (see below), so XCUI cannot select one.

The fade itself is a pixel property under gaze. The frame evidence above shows the
layout no longer moves; the wearer confirms the visual.

## Library sidebar and toolbar accept no synthetic input

Rendered and present in the hierarchy, refused by XCUI:

```
FileBrowsing-SourcesSidebar-sourceMore        {{144.0, 20.0}, {60.0, 60.0}}
FileBrowsing-FilesScreen-sidebarToggle        {{244.0, 24.0}, {60.0, 60.0}}
FileBrowsing-FilesScreen-sort                 {{904.0, 24.0}, {60.0, 60.0}}
FileBrowsing-Manage-button                    {{972.0, 32.0}, {44.0, 44.0}}
FileBrowsing-SourcesSidebar-source-<uuid>     rows at y 136 and y 184
```

`MediaLibrary-grid-folder-Samples` in the same window taps successfully, so the
session holds input ownership. Screenshot `933327b8-…png` shows the sidebar, its
More button, and the toolbar all drawn, so this is not a hidden-view artifact.
This is the wearer's standing report that the More button cannot be gazed or
clicked, and it covers more controls than that one button.

## Format detection reads no projection from 180_3D.mp4

```
projection=flat;sourceContentKind=rectilinear;effectiveContentIsPanoramic=false
providerProjectionKind=unknown;sampleProjectionKind=none;formatProvenance=source
```

`playback_mode_matrix.py` expects `presentation=panorama` on open for this clip, so
every path built on that expectation fails at step 1 against this build. Nothing in
this batch touches format detection, so the mismatch predates it and is unresolved.
