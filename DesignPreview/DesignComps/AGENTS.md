# DesignComps Agent Notes

`DesignComps` holds page-level SwiftUI design comps derived from `docs/designs/`.
These files are visual planning surfaces. They are not the final Fake UX, and they
do not connect to real backend or playback flows.

## Terms

- `Sidebar`: the visionOS window-side navigation strip that sits outside the main `WindowGroup` content panel. It is not the Files page's internal left column.
- `Source Pane`: the Files-scene location pane for sources such as local storage, SMB, WebDAV, and folder position.
- `Player Control Panel`: the complete playback control overlay, including bottom transport controls, progress, top title area, back control, and auxiliary controls.
- `Timeline`: the secondary precision timeline used for detailed scrubbing and frame-level review.
- `Video Detail Page`: the second-level page opened from a video card before playback. It carries preview, metadata, subtitles, audio tracks, scene choice, and the play entry.
- `Empty Panel`: the system `WindowGroup` shell for the window-mode app surface. It is a Scene-level window, not a Page and not a View asset.
- `Window Content`: page content placed inside the system `WindowGroup` shell. Home, Files, Video Detail, and settings comps start from this layer.
- `Preview Stage`: a Canvas-only review wrapper that can show the `Window Content` beside the window-side `Sidebar`. It is not app navigation.
- `DesignCompsPreviewGallery`: the Xcode Canvas review entry that groups named previews for existing design comps. It is not app navigation and not Fake UX.

## Page Matrix

Create pages gradually after the layout semantics are stable. Do not create empty
Swift page files only to reserve names.

- Home: first home view and later home variants.
- Files: folder grid, folder list, source selection, and video detail.
- Settings: Apple Settings-style multi-column settings pages.
- Player: control panel visible, controls hidden, timeline expanded, and top-level left/right panels when those panel options need review.
- Windows: Scene-level system windows such as Empty Panel.
- Assets: reusable visual-only surfaces such as icons and non-window visual assets.

## Build Rules

- Keep `ContentView.swift`, `ComponentLibrary.swift`, and `SharedComponents.swift` as the confirmed component library / UI kit source unless the user explicitly asks to revise them.
- Prefer existing components and `DesignTokens` before adding new local structures.
- New page comps start from `EmptyPanelWindowContent` / system `WindowGroup` semantics. Page files define the content inside the window; the window-side `Sidebar` belongs to the preview stage or system scene layer, not inside the page content.
- New page comps should start as layout skeletons: named regions, spacing, hierarchy, and existing component placement. Do not invent final Fake UX flow.
- Empty Panel must be represented by a `WindowGroup` with its default size declared on the Scene. Do not fake the system window shell with a large framed View, custom rounded rectangle, or `glassBackgroundEffect` inside Canvas.
- Use `DesignCompsPreviewGallery.swift` when multiple comps need to appear as named previews in one Canvas context. Page files keep their own local `#Preview` for single-page work.
- Use short region labels when a skeleton needs review clarity. These labels are design-review labels, not product copy.
- Do not hand-roll controls already present in the component library. Reuse `PlayerProgressStrip`, `PlayerControlBar`, `VideoCardLarge`, `FolderCard`, `FileListRow`, `MenuItemRow`, `SceneCardMedium`, `ViewModeCapsuleControl`, and related components before creating local placeholders.
- Avoid wiring real business logic. Local preview state is allowed only when it helps inspect a visual state.
- Do not expand player submenus until their top-level panel semantics are stable.
