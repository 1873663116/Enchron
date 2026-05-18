# ExecPlan018 — T1.4 全景视频完善（域层 stub 填充）

**Round**: 9
**Pipeline State**: EXECUTING
**目标**: 填充 T1.4 相关的 5 个 stub 源文件，使 19 个 failing tests 变绿

## 变更清单

### 1. StereoMode.swift (7 tests)
- leftEyeUVRect: SBS → (0,0,0.5,1.0), OU → (0,0,1.0,0.5)
- rightEyeUVRect: SBS → (0.5,0,0.5,1.0), OU → (0,0.5,1.0,0.5)
- outputDimensions: SBS → (w/2,h), OU → (w,h/2)

### 2. HemisphereMeshConfiguration.swift (4 tests)
- uRange: 0.25...0.75 (前半球 UV)
- longitudeRange: -π/2...π/2
- vertexCount: (stacks+1) * (slices+1)
- vRange: 0.0...1.0

### 3. FisheyeRemapConfiguration.swift (3 tests)
- 默认 FOV 改为 π/2
- sampleCoordinate: equidistant fisheye → equirectangular 映射
  - 输出 UV → 球面坐标 → 3D 方向 → 鱼眼投影坐标
  - 超出 FOV 返回 nil

### 4. ProjectionType.swift (5 tests, 共 3 计算属性)
- isStereo3D: stereoscopicSBS/OU → true
- requiresHemisphereMesh: panorama180 → true
- requiresFisheyeRemap: fisheye → true

### 5. ProjectionDetection.swift (2 tests)
- 在 GSpherical 检测中增加 fisheye/equidistant_fisheye → .fisheye

## 验证
- `swift test`: 19 个 T1.4 tests 从 FAIL → PASS
- 原有 223 个 tests 仍然全部 PASS
- 目标: 242 passed / 6 failed (T1.5 remaining)
