# DesignComps Agent Notes

`DesignComps` holds page-level SwiftUI design comps derived from `docs/designs/`.
These files are visual planning surfaces. They are not the final Fake UX, and they
do not connect to real backend or playback flows.

## Terms

- `Sidebar`: the primary app navigation surface for main scenes such as Files and Settings.
- `Source Pane`: the Files-scene location pane for sources such as local storage, SMB, WebDAV, and folder position.
- `Player Control Panel`: the complete playback control overlay, including bottom transport controls, progress, top title area, back control, and auxiliary controls.
- `Timeline`: the secondary precision timeline used for detailed scrubbing and frame-level review.
- `Video Detail Page`: the second-level page opened from a video card before playback. It carries preview, metadata, subtitles, audio tracks, scene choice, and the play entry.

## Page Matrix

Create pages gradually after the layout semantics are stable. Do not create empty
Swift page files only to reserve names.

- Home: first home view and later home variants.
- Files: folder grid, folder list, source selection, and video detail.
- Settings: Apple Settings-style multi-column settings pages.
- Player: control panel visible, controls hidden, timeline expanded, and top-level left/right panels when those panel options need review.
- Assets: reusable visual-only surfaces such as an empty glass panel.

## Build Rules

- Keep `ContentView.swift`, `ComponentLibrary.swift`, and `SharedComponents.swift` as the confirmed component library / UI kit source unless the user explicitly asks to revise them.
- Prefer existing components and `DesignTokens` before adding new local structures.
- New page comps should start as layout skeletons: parameterized artboard size, named regions, spacing, and hierarchy.
- Use short region labels when a skeleton needs review clarity. These labels are design-review labels, not product copy.
- Avoid wiring real business logic. Local preview state is allowed only when it helps inspect a visual state.
- Do not expand player submenus until their top-level panel semantics are stable.
