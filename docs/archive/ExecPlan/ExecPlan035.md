# ExecPlan035 — 测试素材元数据修复

## 目标
修复 Round 3 (T0.3) 生成的 4 个测试素材缺少投影/立体元数据的问题，使 ProjectionDetection 自动检测能正常工作。

## 问题根因
Round 3 使用 ffmpeg 生成素材时只验证了容器/编码/色彩属性，未验证投影/立体元数据：
- SBS/OU: 缺少 `st3d` (Stereo 3D) box → mpv `video-params/stereo-in` 为空
- 180° VR: 缺少 `sv3d` (Spherical Mapping) box → mpv `metadata/by-key/GSpherical:Spherical` 为空
- 鱼眼: 缺少 GSpherical XMP 元数据 → mpv `metadata/by-key/GSpherical:ProjectionType` 为空

## 修复方案
1. **SBS/OU/180°**: 使用 Google spatial-media 工具注入 `st3d` + `sv3d` + UUID(XMP) 元数据
2. **鱼眼**: 通过 Python 修改 spatial-media 常量，注入 `ProjectionType=fisheye` 的 XMP

## 修复结果
| 素材 | 修复前 | 修复后 | 预期检测结果 |
|------|--------|--------|------------|
| SBS-stereo3d-test.mp4 | 无 side data | Stereo 3D: side by side | `.stereoscopicSBS` |
| OU-stereo3d-test.mp4 | 无 side data | Stereo 3D: top and bottom | `.stereoscopicOU` |
| 180-vr-test.mp4 | 无 side data | Spherical Mapping: equirectangular | `.panorama360` (FOV TODO) |
| fisheye-test.mp4 | 无 XMP | GSpherical:ProjectionType=fisheye | `.fisheye` |

## 影响的 QA 路径
- QA-F01 (SBS 3D): PARTIAL → 预期 PASS（素材可自动检测）
- QA-F02 (OU 3D): PARTIAL → 预期 PASS（素材可自动检测）
- QA-E02 (180° VR): FAIL → 预期 PARTIAL（素材球形元数据就绪，但 FOV 仍 hardcoded nil → 误判为 360°）
- QA-E03 (鱼眼): FAIL → 预期 PASS（素材可自动检测为 fisheye）

## 测试验证
- swift test: 247 passed, 1 skipped, 0 failures
- ffprobe 验证全部 12 个素材元数据正确
