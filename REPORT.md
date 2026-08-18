# Docked spatial tap fix report

## Result

Docked playback now receives gaze-and-pinch input through a dedicated invisible RealityKit plate instead of the `VideoPlayerComponent` entity. The video entity no longer has `InputTargetComponent` or `CollisionComponent` in any presentation.

The plate is a child of the Docked video entity. Its local collision box uses `VideoPlayerComponent.playerScreenSize`, and the parent supplies the current Docked `screenScale`, distance, elevation, and orientation. A `VideoSizeDidChange` event refreshes the collision box when RealityKit publishes the actual video dimensions. The plate sits 0.01 metres in front of the video in local positive Z, matching the existing front-facing subtitle placement convention.

Docked input ownership now names `dockedInteractionSurface`. The shared spatial-tap handler accepts this entity, continues to exclude the controls attachment, and keeps the device-readable probe records in the form `spatialTap entity=... accepted=...`. Panorama and window or portal input receivers were not changed.

## Tests changed

`PlaybackRealityPresenterTests` now verifies these contracts:

- Docked configuration removes stale input-target and collision components from the video entity.
- The stored Docked input plate has an input target and a thin box collider sized to the supplied video aspect.
- Parenting the plate to a scaled video entity makes it inherit the Docked screen scale.
- Docked input ownership resolves to the new interaction plate.

## Verification

The required simulator build passed with exit code 0:

```text
xcodebuild build -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -quiet
```

The output contained the repository's existing SwiftLint and visionOS 27 SDK deprecation warnings.

The focused final regression run passed all three Docked contract tests with exit code 0:

```text
xcodebuild test -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -only-testing:EnchronAppTests/PlaybackRealityPresenterTests/testDockedVideoSurfaceOmitsRealityKitHitTargets \
  -only-testing:EnchronAppTests/PlaybackRealityPresenterTests/testDockedUsesInteractionPlateSizedFromVideoAspectAndScreenScale \
  -only-testing:EnchronAppTests/PlaybackRealityPresenterTests/testEachPresentationHasExactlyOneDirectSurfaceInputOwner -quiet

Result: Passed, 3 tests, 0 failures.
```

The required complete class command ran, but it was not all green:

```text
xcodebuild test -project Enchron.xcodeproj -scheme Enchron -destination 'platform=visionOS Simulator,name=Apple Vision Pro' -only-testing:EnchronAppTests/PlaybackRealityPresenterTests -quiet

Result: Failed, 30 tests, 26 passed, 4 failed.
```

All four failures are unchanged environment-resource tests. Each failed with `resourceNotFound("world")`:

- `testClearingEnvironmentDisablesEveryEnvironmentBackdrop`
- `testDockingWorldCanLoadFromProductResources`
- `testScenicEnvironmentReplacesSkyboxWithTintedPlaceholder`
- `testSkyboxRestoresTheProductResourceWithoutAnEffect`

The compiled `RealityKitContent.reality` manifest contains `Immersive.usda`, `Scene.usda`, and related assets, but no resource named `world`. I did not alter that unrelated resource contract in this spatial-input commit.

A failing-before assertion was not captured. The first pre-fix attempt could not resolve the locally absent `PlaybackFFmpeg.xcframework`; after building that ignored dependency, Xcode stalled while starting the simulator test session. The old source contract was nevertheless direct: Docked installed `InputTargetComponent` and a hardcoded `[1.8, 1, 0.01]` collision box on the video entity. The final focused tests exercise the replacement contract and pass.

## Wearer verification still required

Real-device pinch verification is out of reach in this environment and was not performed. A wearer should open a flat video in Docked presentation, pinch the virtual screen at more than one screen scale and aspect ratio, and confirm that playback controls toggle. Device evidence should include `Documents/surface-tap-probe.log` lines such as:

```text
spatialTap entity=EnchronDockedInput.surface accepted=true
toggle source=spatialTap showControls=...
```
