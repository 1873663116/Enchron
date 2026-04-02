# ExecPlan020 — T1.4 Fisheye Remap Metal Compute Shader

## Goal
Implement the fisheye-to-equirectangular remapping as a Metal compute shader, integrated into PanoramaLayerBridge, so that fisheye projection videos display correctly on the panorama sphere.

## Context
- Domain layer done: `FisheyeRemapConfiguration.sampleCoordinate()` has the algorithm (Round 9)
- `ProjectionType.fisheye.requiresFisheyeRemap == true` (tested)
- `ProjectionDetection` already detects fisheye from metadata
- PanoramaLayerBridge currently does blit copy (+ optional stereo crop)
- Need: compute dispatch path for fisheye remap

## Changes

### 1. VideoShaders.metal — Add `fisheye_remap` compute kernel
- Port FisheyeRemapConfiguration.sampleCoordinate algorithm to Metal
- Input: fisheye texture (sample access), Output: equirectangular texture (write access)
- Uniforms: fovRadiusRadians (float)
- Bilinear sampling via constexpr sampler
- Out-of-FOV pixels → black

### 2. PanoramaLayerBridge.swift — Add fisheye compute dispatch path
- New property: `fisheyeRemapConfig: SpatialSceneDomain.FisheyeRemapConfiguration?`
- Lazy-init compute pipeline from default library "fisheye_remap"
- In handleDisplayLink: when fisheyeRemapConfig != nil, dispatch compute instead of blit
- LowLevelTexture usage: add .shaderWrite when fisheye active

### 3. ImmersiveSpaceView.swift — Wire fisheyeRemapConfig
- In .panorama case: set `panoramaBridge.fisheyeRemapConfig` based on `effectiveProjectionType.requiresFisheyeRemap`
- Clear config when leaving panorama or when projection doesn't need remap

### 4. TODOS.md — Mark completed items
- T1.1 all items [x] (done in Round 6)
- T1.3 swift test item still unchecked (deferred to Phase 2)
- T1.4 fisheye item [x] after implementation
- T1.5 mode switching UI + graceful transition [x] (found already implemented)
- T1.6 items [x] where applicable (SceneSelectorView done in Round 8, no placeholders found)
