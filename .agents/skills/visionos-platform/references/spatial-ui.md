# Spatial UI, SwiftUI Controls, Gaze, Ornaments

Use for `PlayerUI`, `DesignPreview`, `Shared/DesignSystem`, `Settings`, SwiftUI
controls, gaze hover, ornaments, spatial layout, menus, buttons, sliders,
accessibility, and component behavior.

## Apple Sources

- Designing for visionOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-visionos/
- Spatial layout: https://developer.apple.com/design/human-interface-guidelines/spatial-layout/
- Windows HIG: https://developer.apple.com/design/human-interface-guidelines/windows
- Ornaments HIG: https://developer.apple.com/design/human-interface-guidelines/ornaments
- Eyes HIG: https://developer.apple.com/design/human-interface-guidelines/eyes
- Gestures HIG: https://developer.apple.com/design/human-interface-guidelines/gestures
- Buttons HIG: https://developer.apple.com/design/human-interface-guidelines/buttons
- Going full screen HIG: https://developer.apple.com/design/human-interface-guidelines/going-full-screen
- Glass background effect: https://developer.apple.com/documentation/swiftui/glassbackgroundeffect
- `glassBackgroundEffect(_:in:displayMode:)`: https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(_:in:displaymode:)
- Hover effect: https://developer.apple.com/documentation/swiftui/view/hovereffect(_:)
- Custom hover effect: https://developer.apple.com/documentation/swiftui/view/hovereffect(in:isenabled:body:)
- Hover content shape: https://developer.apple.com/documentation/swiftui/contentshapekinds/hovereffect
- Content shape: https://developer.apple.com/documentation/swiftui/view/contentshape(_:_:eofill:)
- SpatialTapGesture: https://developer.apple.com/documentation/swiftui/spatialtapgesture
- 3D SpatialTapGesture initializer: https://developer.apple.com/documentation/swiftui/spatialtapgesture/init(count:coordinatespace3d:)
- 3D DragGesture initializer: https://developer.apple.com/documentation/swiftui/draggesture/init(minimumdistance:coordinatespace3d:)
- GeometryReader3D: https://developer.apple.com/documentation/swiftui/geometryreader3d
- Spatial framework: https://developer.apple.com/documentation/spatial
- CoordinateSpace3D: https://developer.apple.com/documentation/spatial/coordinatespace3d
- Improving accessibility support in your visionOS app: https://developer.apple.com/documentation/visionos/improving-accessibility-support-in-your-app
- Accessibility: https://developer.apple.com/documentation/accessibility

## Correct Decisions

- visionOS primary interaction is gaze plus indirect gesture.
- Standard controls carry platform behavior that custom gestures do not.
- Prefer `Button`, `Toggle`, `Slider`, `TabView`, toolbars, menus, and sheets
  unless the interaction genuinely needs custom gesture data.
- Hit regions need visionOS spacing. Use Apple HIG values for target size and
  spacing; do not inherit iOS-only target assumptions.
- Use `hoverEffect` and `contentShape(.hoverEffect, shape)` to define gaze/focus
  affordance.
- Keep controls semantic. Custom hover effects are allowed when implemented
  through SwiftUI hover APIs or button styles and when they preserve hit region,
  focus behavior, accessibility, and comfort.
- Treat `onHover` as pointer-style behavior that needs device verification
  before it becomes product behavior.
- Toolbars and tab bars can become ornaments in visionOS. Custom ornaments are
  for controls related to a window that should stay near but not crowd content.
- Glass shape, clip shape, content shape, and hit region need deliberate
  alignment.
- Avoid visual density that feels like desktop chrome floating in space.

## iOS/macOS Conflicts

- Pointer hover and gaze hover are different interactions.
- A 44 pt touch target is not enough as the default visionOS target.
- `TapGesture` is not a semantic `Button`; use gestures for non-button
  interactions or when location data is essential.
- Do not replace a semantic `Button` with a raw gesture just to get a custom
  hover look. Preserve system semantics first, then customize.
- Do not add depth to text for decoration. Depth can reduce readability and
  comfort.
- Do not import dense macOS sidebars/inspectors blindly. Spatial layout values
  comfort and field-of-view discipline over desktop information density.
- Do not assume every iPad-style popover/sheet layout is comfortable in a
  spatial window.

## Enchron Checkpoints

- `DesignTokens` remain the source for style values, spacing, animation, and
  press feedback.
- Component-library changes should be checked against `DesignPreview/AGENTS.md`
  and existing components before adding new shapes.
- Controls shared by window and immersive playback should be designed for both
  surfaces, not optimized only for the window path.
- Use `accessibilityIdentifier` for test targeting. Use explicit labels for
  icon-only or custom controls, verify derived labels for text controls, and add
  accessibility actions for nonstandard playback controls.
- For RealityKit entities that can be discovered or activated, add appropriate
  `AccessibilityComponent` metadata and test with VoiceOver or documented
  assistive features.
