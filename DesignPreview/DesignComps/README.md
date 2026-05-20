# Design Comps

`DesignComps` stores high-fidelity SwiftUI screen comps derived from `docs/designs/`.

These files are visual design assets, not the final Fake UX app and not production backend flow. A comp may include local hover, press, reveal, menu, sheet, or other small interactions when needed to judge the design.

Do not invent the number of comps. First inspect the HTML files in `docs/designs/`, then create comps according to the actual pages, states, overlays, and assets present there.

## Folders

- `Pages/`: full page or screen comps from the HTML designs.
- `Sections/`: large page portions extracted only when a page is too detailed to build safely in one pass.
- `Overlays/`: sheets, popovers, menus, share panels, and other floating surfaces.
- `Assets/`: SwiftUI asset comps such as app icon treatments or reusable visual-only scene assets.
- `Fixtures/`: fake data used only by DesignComps.

Stable visual components already confirmed in `ContentView`, `ComponentLibrary.swift`, and `SharedComponents.swift` should be reused or referenced. Do not restyle those confirmed components while building comps unless the user explicitly asks for a component revision.
