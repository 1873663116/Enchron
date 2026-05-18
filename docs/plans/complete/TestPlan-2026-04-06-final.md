---
title: "TestPlan: Enchron V2 综合验收"
date: 2026-04-06
source: docs/plans/active/ExecPlan.md
---

# TestPlan: Enchron V2 综合验收

## 验收范围

本 TestPlan 覆盖 ExecPlan 9 个实施单元的验证，分三层：单元测试、结构审计、真机验证。

## 测试档位

- `/qa` Standard 档位（严重 + 高 + 中等）
- `/e2e` 结构审计 + 无障碍审计 + 交互测试
- **不使用 Simulator 截图测试**

## Accessibility 验收标准

所有可交互元素必须同时具备：
- `accessibilityIdentifier`（UI 测试定位）
- `accessibilityLabel`（VoiceOver 语义）

### 必须覆盖的元素

| View | 元素 |
|------|------|
| PlayerControlsView | Menu / Rewind / Play-Pause / Forward / Settings 按钮 |
| Menu 子项 | HDR Toggle / Subtitles / Audio Track / Playback Speed |
| Settings 子项 | Playback Mode 各项 / 3D 开关 / Environment |
| VideoCardView | 卡片整体 |
| VideoDetailView | 返回按钮 / HDR Toggle / 沉浸模式 Picker / Play 按钮 |
| ContentGridView | 骨架屏容器 |

## 测试矩阵

### 1. P0 菜单交互回归（Unit 1）

| 场景 | 预期 |
|------|------|
| 播放状态下点击 Menu，展开二级菜单 | 菜单稳定显示，子项可点击 |
| 播放状态下点击 Settings，展开三级菜单 | 菜单不闪烁，可交互 |
| 播放开始后立即点击 Menu（<2s） | 菜单正常出现 |
| 暂停→播放→再次点击菜单 | 交互正常（回归原有暂停后恢复） |
| 快速连续点击 Menu 5 次 | 无闪烁或 UI 卡死 |

### 2. 三轴域模型（Unit 2）

| 场景 | 预期 |
|------|------|
| `ProjectionType.flat.isPanoramic` | `false` |
| `ProjectionType.equirectangular360.isPanoramic` | `true` |
| `StereoLayout.mono.leftEyeUVRect` | `{0,0,1,1}` |
| `StereoLayout.sideBySide.leftEyeUVRect` | `{0,0,0.5,1}` |
| `MediaProfile(projectionType: .fisheye, stereoLayout: .sideBySide)` | 可构造（路由层强制 mono） |
| 全局无 `StereoMode`/`stereoscopicSBS`/`stereoscopicOU` 引用 | 编译通过 |

### 3. ProjectionDetection + HDR（Unit 3）

| 输入 | 预期输出 |
|------|---------|
| `stereo3dIn = "sbs2l"` | `(.flat, .sideBySide)` |
| `stereo3dIn = "ab2r"` | `(.flat, .topBottom)` |
| `stereo3dIn = "mono"` + 球面元数据 | `(.equirectangular360, .mono)` |
| `stereo3dIn = "sbs2l"` + fisheye | `(.fisheye, .mono)` — fisheye 强制覆盖 |
| `stereo3dIn = "side_by_side_left"` | `(.flat, .mono)` — 死代码已删除 |
| `gamma = "pq"` | `.hdr10` |
| `gamma = "hlg"` | `.hlg` |
| `gamma = "bt.1886"` | `.sdr` |
| `video-params/hdr-format` | 不再被调用 |

### 4. 三轴路由约束矩阵（Unit 4）

| ProjectionType | StereoLayout | 默认路由 |
|---------------|-------------|---------|
| `.flat` | `.mono` | `.window` |
| `.flat` | `.sideBySide` | `.immersive` |
| `.flat` | `.topBottom` | `.immersive` |
| `.equirectangular360` | `.mono` | `.panorama` |
| `.equirectangular180` | `.sideBySide` | `.panorama` |
| `.fisheye` | `.mono` | `.panorama` |

| 约束 | 预期 |
|------|------|
| `allowedModes(.flat)` | 不包含 `.panorama` |
| `allowedModes(.equirectangular360)` | 包含全部三项 |
| `manualOverride = .panorama` + `.flat` | 被拦截，回退 `.window` |
| `manualOverride = .immersive` + `.equirectangular360` | 合法，返回 `.immersive` |

### 5. 播放控件 UI 对齐（Unit 5）

| 场景 | 预期 |
|------|------|
| SDR 内容 | Menu 中无 HDR 行 |
| HDR10 内容 | Menu 中显示 "HDR10" + Toggle |
| Dolby Vision 内容 | Menu 中显示 "Dolby Vision" + Toggle |
| flat 内容 | Settings 中 Panorama 项为 disabled |
| equirectangular360 | Settings 中全部 Playback Mode 可点击 |
| mono 内容 | 3D 开关整行 disabled |
| SBS 内容 | 3D 开关默认选中 Side-by-Side，可切 Off |

### 6. VideoDetailView（Unit 6）

| 场景 | 预期 |
|------|------|
| 打开详情页 | 返回按钮可见可点击，dismiss sheet |
| SDR 视频 | HDR 开关不显示 |
| HDR 视频（ready） | HDR 开关显示 |
| flat 内容 | Panorama 选项 disabled |

### 7. 缩略图（Unit 7）

| 场景 | 预期 |
|------|------|
| 首次加载视频列表 | 异步显示缩略图，占位图先显示 |
| 二次进入同一页面 | 缩略图无闪烁（命中缓存） |
| 有内嵌封面的 MKV | 显示封面而非帧截图 |
| 文件损坏或超时 | 返回 nil，显示占位图标，不崩溃 |
| LazyVGrid 快速滚动 | 按需加载，不阻塞 UI |

### 8. 数据源切换（Unit 8）

| 场景 | 预期 |
|------|------|
| 切换到 WebDAV | 立即看到骨架屏，不停留旧内容 |
| 连接成功 | 骨架屏替换为实际内容 |
| 连接失败 | 显示错误态 |
| 快速连续切换两次 | 显示最后一次切换的结果 |

### 9. 端到端集成

| 场景 | 预期 |
|------|------|
| 切换数据源 → 加载 → 选择视频 → 详情页 → 播放 → 菜单交互 | 全流程无卡顿无崩溃 |
| 全量 12 种 (ProjectionType, StereoLayout) 组合 | allowedModes 输出与约束矩阵一致 |
| P0 菜单回归 | 播放中菜单全程可交互 |

## REGRESSION.md 新增项（验收时确认）

- P0 菜单交互：播放中菜单展开可交互
- 三轴路由约束矩阵：flat 禁 panorama，3 种 ILLEGAL 组合
- HDR 检测路径：gamma-based 决策树
- 缩略图加载：NSCache + 磁盘两级缓存
- 数据源切换加载态：立即跳转 + 骨架屏
