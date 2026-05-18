# ExecPlan 038 — UX-01 DragRotationModifier

> Round 19 | Phase 2 T2.2 | 2026-04-02

## Goal
Implement drag-to-rotate interaction for spatial entities in immersive/panorama modes, following HelloWorld's DragRotationModifier pattern.

## Changes
1. NEW: `XrPlayer/SpatialScene/Modifiers/DragRotationModifier.swift`
   - `DragGesture().targetedToAnyEntity()` for spatial gesture detection
   - `.interactiveSpring` during drag, `.spring` + predictedEndLocation3D for inertia
   - Yaw unlimited (look-around), pitch limited ±30° (prevent disorientation)
   - View extension `.dragRotation()` for clean API

2. EDIT: `PanoramaSphereEntity.swift`
   - Add `InputTargetComponent` + `CollisionComponent(shapes: [.generateSphere(radius:)])`

3. EDIT: `VirtualScreenEntity.swift`
   - Add `InputTargetComponent` + `CollisionComponent`

4. EDIT: `ImmersiveSpaceView.swift`
   - Apply `.dragRotation()` to RealityView

## QA Impact
- QA-H04 (捏合拖拽): FAIL → expected PASS (spatial drag rotation)
- QA-D01 (沉浸播放): quality improvement (virtual screen repositionable)
