# DesignComps Agent Notes

`DesignComps` holds page-level SwiftUI design comps derived from `docs/designs/`.
These files are visual planning surfaces. They are not the final Fake UX, and they
do not connect to real backend or playback flows.

## Terms

- `Sidebar`: the visionOS window-side navigation strip that sits outside the main `WindowGroup` content panel. It is not the Files page's internal left column.
- `Source Pane`: the Files-scene location pane for sources such as local storage, SMB, WebDAV, and folder position.
- `Player Control Panel`: the complete playback control overlay, including bottom transport controls, progress, top title area, back control, and auxiliary controls.
- `Timeline`: the secondary precision timeline used for detailed scrubbing and frame-level review.
- `Playback / Window Interaction Page`: the window-mode playback page that gathers playback controls, detail panels, timeline states, menus, and other windowed interactions that need design review.
- `Empty Panel`: the system `WindowGroup` shell for the window-mode app surface. It is a Scene-level window, not a Page and not a View asset.
- `Window Content`: page content placed inside the system `WindowGroup` shell. Home, Files, Video Detail, and settings comps start from this layer.
- `Preview Stage`: a Canvas-only review wrapper that can show the `Window Content` beside the window-side `Sidebar`. It is not app navigation.
- `DesignCompsPreviewGallery`: the Xcode Canvas review entry that groups named previews for existing design comps. It is not app navigation and not Fake UX.

## Page Matrix

Create only the two current window-mode pages. Do not create empty Swift page
files only to reserve names, and do not split every interaction into a separate
page.

- Files: first-launch file browsing, source selection, folder grid/list, search, filters, and file-detail entry states.
- Playback / Window Interaction: video detail, playback controls, control-hidden state, timeline expanded state, settings-style panels, menus, sheets, and other windowed interactions.
- Out of scope for this pass: immersive space pages and panorama mode pages.
- Assets: reusable visual-only surfaces such as icons and non-window visual assets.

## Build Rules

- Keep `ContentView.swift`, `ComponentLibrary.swift`, and `SharedComponents.swift` as the confirmed component library / UI kit source unless the user explicitly asks to revise them.
- Directly reuse existing components and `DesignTokens` before adding new local structures. Do not copy component internals into a page to approximate the same look.
- New page comps start from `EmptyPanelWindowContent` / system `WindowGroup` semantics. Page files define the content inside the window; the window-side `Sidebar` belongs to the preview stage or system scene layer, not inside the page content.
- New page comps should start as layout skeletons: named regions, spacing, hierarchy, and existing component placement. Do not invent final Fake UX flow.
- Empty Panel must be represented by a `WindowGroup` with its default size declared on the Scene. Do not fake the system window shell with a large framed View, custom rounded rectangle, or `glassBackgroundEffect` inside Canvas.
- Use `DesignCompsPreviewGallery.swift` as the current app-first-launch Canvas entry. Page-local `#Preview` entries are optional during isolated component work and should not duplicate the root app preview.
- Use short region labels when a skeleton needs review clarity. These labels are design-review labels, not product copy.
- Do not hand-roll controls already present in the component library. Directly call `PlayerProgressStrip`, `PlayerControlBar`, `VideoCardLarge`, `FolderCard`, `FileListRow`, `MenuItemRow`, `SceneCardMedium`, `ViewModeCapsuleControl`, `MockBreadcrumb`, `PathBreadcrumbMenu`, `SearchInputCapsule`, `FilterPillBar`, `SourcePaneRow`, and related components before creating local placeholders.
- Avoid wiring real business logic. Local preview state is allowed only when it helps inspect a visual state.
- Do not expand player submenus until their top-level panel semantics are stable.
