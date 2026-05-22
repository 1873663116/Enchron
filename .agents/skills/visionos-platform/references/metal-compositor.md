# Metal, Compositor Services, Custom Render Loops

Use for custom Metal rendering, MPV layer output, future fully immersive
renderer work, stereoscopic drawing, Compositor Services, frame timing, and
immersive Metal interaction.

## Apple Sources

- Compositor Services: https://developer.apple.com/documentation/compositorservices
- Drawing fully immersive content using Metal: https://developer.apple.com/documentation/compositorservices/drawing-fully-immersive-content-using-metal
- Controlling Metal rendering immersion level: https://developer.apple.com/documentation/compositorservices/controlling-metal-rendering-immersion-level
- Interacting with virtual content blended with passthrough: https://developer.apple.com/documentation/compositorservices/interacting-with-virtual-content-blended-with-passthrough
- Metal: https://developer.apple.com/documentation/metal
- HDR content in Metal: https://developer.apple.com/documentation/metal/hdr-content

## Correct Decisions

- Use Compositor Services when drawing fully immersive content with a custom
  Metal renderer.
- `CompositorLayer` is an `ImmersiveSpace` content path for custom Metal
  rendering. Its supported immersion behavior is OS-version- and
  configuration-specific; verify full, mixed, and progressive paths in current
  Compositor Services docs before deciding.
- Custom Metal immersive rendering means owning stereoscopic rendering, frame
  timing, and the compositor contract.
- If RealityKit can express the scene, prefer RealityKit before dropping to
  Compositor Services.
- Progressive Metal immersion requires explicit support for the current
  Compositor Services progressive-immersion contract.
- Keep render-loop work out of SwiftUI body/update churn.

## iOS/macOS Conflicts

- A working `MTKView` or `CAMetalLayer` in a 2D window is not a complete
  fully-immersive renderer.
- Do not launch directly into full immersion unless there is a deliberate
  product reason and the required scene-role configuration.
- Do not assume a `CompositorLayer` always means full immersion, or that SwiftUI
  immersion style modifiers have the same effect for every Compositor Services
  configuration.
- Do not use desktop Metal swapchain assumptions for visionOS compositor work.
- Do not treat HDR layer configuration as enough evidence that immersive
  RealityKit or compositor output is correct.

## Enchron Checkpoints

- MPV `CAMetalLayer` output in window mode, panorama bridge output, and any
  future fully immersive renderer should be documented as separate render
  contracts.
- HDR/EDR Metal changes should include device verification when visual output is
  the claim.
- Compute/copy paths between MPV output and RealityKit textures need explicit
  ownership of color space and timing.
