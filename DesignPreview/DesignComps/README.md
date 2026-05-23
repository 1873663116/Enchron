# Design Comps

`DesignComps` stores high-fidelity SwiftUI screen comps derived from `docs/designs/`.

These files are visual design assets, not the final Fake UX app and not production backend flow. A comp may include local hover, press, reveal, menu, sheet, or other small interactions when needed to judge the design.

Do not invent the number of comps. The current DesignPreview pass uses two window-mode pages: Files and Playback / Window Interaction. These pages gather the windowed interactions that need review. Immersive space and panorama mode pages are outside this pass.

## Folders

- `Pages/`: the two current window-mode page comps from the HTML designs.
- `Sections/`: large page portions extracted only when a page is too detailed to build safely in one pass.
- `Overlays/`: sheets, popovers, menus, share panels, and other floating surfaces.
- `Assets/`: SwiftUI asset comps such as app icon treatments or reusable visual-only scene assets.
- `Fixtures/`: fake data used only by DesignComps.

Stable visual components already confirmed in `ContentView`, `ComponentLibrary.swift`, and `SharedComponents.swift` must be directly reused. Do not restyle or locally reimplement those confirmed components while building comps unless the user explicitly asks for a component revision.
