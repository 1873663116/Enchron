# QA Report: Enchron V2 综合验收 — Standard 档位

**日期**: 2026-04-06  
**档位**: Standard（严重 + 高 + 中等）  
**TestPlan**: docs/plans/active/TestPlan.md  
**分支**: MinimaxTest  
**结论**: **PASS**

---

## 1. 构建验证

| 检查 | 结果 |
|------|------|
| visionOS Simulator 构建（Xcode） | PASS — 0 errors, 65 warnings（全部为 SwiftLint 风格警告，无编译错误） |
| Swift Package 单元测试 | PASS — 317 tests, 1 skipped（WebDAV 集成测试，需要 env vars）, 0 failures |

---

## 2. 单元测试覆盖

| 测试集 | 数量 | 结果 |
|--------|------|------|
| PlaybackModeRoutingTests（Unit 4） | 26 | PASS |
| ProjectionDetectionExtendedTests（Unit 3） | 17 | PASS |
| ProjectionDetectionTests（Unit 3） | 3 | PASS |
| HDRTypeExtendedTests / PlaybackFlowTests（Unit 3） | 19 | PASS |
| V02Tests / V03Tests / V04Tests / CoreLogicTests 等 | 252 | PASS |

---

## 3. 测试矩阵逐项结论（静态代码审计）

### Unit 1: SeekBarView 属性隔离（P0 菜单回归）

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| `SeekBarView` 是独立 private struct | 代码审计：PlayerControlsView.swift:486 | PASS |
| `playbackPosition` 仅在 SeekBarView 读取 | 代码审计：controlBarPill / leftMenu / rightMenu 均不含 playbackPosition 引用 | PASS |
| `leftMenu` / `rightMenu` 不读取 playbackPosition | 代码审计确认 | PASS |

### Unit 2: ProjectionType / StereoLayout 三轴域模型

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| `ProjectionType` 4 cases（flat/equirectangular360/equirectangular180/fisheye） | ProjectionType.swift 确认 | PASS |
| `ProjectionType.flat.isPanoramic == false` | 代码审计 | PASS |
| `ProjectionType.equirectangular360.isPanoramic == true` | 代码审计 | PASS |
| `StereoLayout.mono.leftEyeUVRect == {0,0,1,1}` | StereoLayout.swift 确认 | PASS |
| `StereoLayout.sideBySide.leftEyeUVRect == {0,0,0.5,1}` | StereoLayout.swift 确认 | PASS |
| `MediaProfile` 含 hasCoverArt / projectionType / stereoLayout / hdrType 字段 | MediaProfile.swift 确认 | PASS |
| 全局无 `StereoMode` / `stereoscopicSBS` / `stereoscopicOU` 引用 | grep 搜索 XrPlayer/ 返回空 | PASS |

### Unit 3: ProjectionDetection + HDR gamma-based 决策树

| 输入 | 预期 | 结论 |
|------|------|------|
| stereo3dIn="sbs2l" | (.flat, .sideBySide) | PASS（代码审计 + 测试） |
| stereo3dIn="ab2r" | (.flat, .topBottom) | PASS（代码审计 + 测试） |
| stereo3dIn="mono" + 球面 | (.equirectangular360, .mono) | PASS |
| stereo3dIn="sbs2l" + fisheye | (.fisheye, .mono) — fisheye 强制覆盖 | PASS |
| stereo3dIn="side_by_side_left" | (.flat, .mono) — 死代码已删除 | PASS（该值落入 else 分支 → .mono） |
| gamma="pq" | .hdr10 | PASS（MPVPlayerAdapter:1326） |
| gamma="hlg" | .hlg | PASS（MPVPlayerAdapter:1316） |
| gamma="bt.1886" | .sdr（无匹配，走 fallback） | PASS |
| video-params/hdr-format | 不再被调用 | PASS（grep 返回空） |

### Unit 4: 三轴路由约束矩阵（26 tests 全覆盖）

| ProjectionType | StereoLayout | 默认路由 | 结论 |
|---------------|-------------|---------|------|
| .flat | .mono | .window | PASS |
| .flat | .sideBySide | .immersive | PASS |
| .flat | .topBottom | .immersive | PASS |
| .equirectangular360 | .mono | .panorama | PASS |
| .equirectangular180 | .sideBySide | .panorama | PASS |
| .fisheye | .mono | .panorama | PASS |

| 约束 | 结论 |
|------|------|
| allowedModes(.flat) 不含 .panorama | PASS |
| allowedModes(.equirectangular360) 含全部三项 | PASS |
| manualOverride=.panorama + .flat → 拦截，回退 .window | PASS |
| manualOverride=.immersive + .equirectangular360 → 合法，返回 .immersive | PASS |

### Unit 5: PlayerControlsView HDR 动态标签 + 3D 开关

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| `isHDRContent` 条件控制 HDR Toggle 显示 | 代码审计 PlayerControlsView:174 | PASS |
| `hdrToggleLabel` 按 hdrType 动态返回 "Dolby Vision" / "HDR10" / "HLG" | 代码审计 PlayerControlsView:236-243 | PASS |
| 3D 开关 disabled 当 `detectedStereoLayout == .mono` | 代码审计 PlayerControlsView:284 | PASS |
| Playback Mode 按 allowedModes 禁用 flat 的 Panorama 项 | 代码审计 PlayerControlsView:266-271 | PASS |

### Unit 5: Accessibility（PlayerControlsView）

| 元素 | accessibilityIdentifier | accessibilityLabel | 结论 |
|------|------------------------|-------------------|------|
| left-menu-button | "left-menu-button" | "Playback Options" | PASS |
| right-menu-button | "right-menu-button" | "Settings" | PASS |
| rewind-button | "rewind-button" | "Rewind 10 seconds" | PASS |
| play-pause-button | "play-pause-button" | 动态（Play/Pause/Replay） | PASS |
| forward-button | "forward-button" | "Forward 10 seconds" | PASS |
| hdr-toggle | "hdr-toggle" | 动态 hdrToggleLabel | PASS |
| subtitles-picker | "subtitles-picker" | "Subtitles" | PASS |
| audio-track-picker | "audio-track-picker" | "Audio Track" | PASS |
| playback-mode-{rawValue} | 动态 | playbackModeLabel | PASS |
| 3d-mode-picker | "3d-mode-picker" | "3D Mode" | PASS |

### Unit 6: VideoDetailView

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| 返回按钮存在（videoDetail.backButton） | 代码审计 VideoDetailView:59 | PASS |
| HDR Toggle 仅在 `hdrType != .sdr` 时显示 | 代码审计 VideoDetailView:529-531 | PASS |
| 沉浸模式 Picker（playbackModePicker） | 代码审计 VideoDetailView:653 | PASS |
| flat 内容 Panorama disabled | 代码审计 VideoDetailView:687 `.disabled(!isAllowed)` | PASS |

### Unit 7: ThumbnailService

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| `@Observable` actor 模型（ThumbnailService） | ThumbnailService.swift:16 | PASS |
| 两级缓存：NSCache hot → disk JPEG cold | ThumbnailCache.swift 确认 | PASS |
| 缓存键 SHA256(path + modifiedAt) | ThumbnailCache:36-45 | PASS |
| 并发限流：local≤3 / remote≤2（AsyncSemaphore） | ThumbnailService:28-29 | PASS |
| 去重：inFlightTasks 防止同 key 重复提取 | ThumbnailService:63-83 | PASS |
| VideoCardView `.task(id: file.id)` 接入 | VideoCardView:43-45 | PASS |

### Unit 8: 数据源切换骨架屏

| 项目 | 验证方式 | 结论 |
|------|---------|------|
| `connectToDataSource` 函数开头立即 `files = []` + `isLoading = true` | FileBrowsingViewModel:141-143 | PASS |
| ContentGridView `isLoading` 分支显示 skeletonGrid | ContentGridView:17-18 | PASS |
| SkeletonCardView shimmer animation（repeatForever） | ContentGridView:44-48 | PASS |
| 连接失败 `isLoading = false` + `lastErrorMessage` | FileBrowsingViewModel:182-185 | PASS |

---

## 4. Accessibility Identifier 审计

| View | 元素 | accessibilityIdentifier | 结论 |
|------|------|------------------------|------|
| PlayerControlsView | 全部必覆盖元素（10项） | 见 Unit 5 表格 | PASS |
| VideoDetailView | backButton / hdrToggle / playbackModePicker / playButton | 全部存在 | PASS |
| VideoCardView | 卡片整体 | "FileBrowsing-VideoCard-button-{file.id}" | PASS |
| ContentGridView | 骨架屏容器 | "FileBrowsing-ContentGrid-skeleton" | PASS |

---

## 5. REGRESSION.md 新增项（TestPlan 要求）

| REG | 标题 | 状态 |
|-----|------|------|
| REG-128 | 播放中菜单全程可交互（P0 回归） | 已新增 |
| REG-129 | 三轴路由约束矩阵（flat 禁 panorama） | 已新增 |
| REG-130 | HDR 检测 gamma-based 决策树 | 已新增 |
| REG-131 | 缩略图两级缓存（NSCache + 磁盘） | 已新增 |
| REG-132 | 数据源切换立即显示骨架屏 | 已新增 |

代码路径映射索引已同步更新。

---

## 6. 已知 P2 问题（noted，不影响 PASS 判定）

| # | 描述 | 位置 | 严重度 |
|---|------|------|--------|
| P2-1 | ThumbnailMPVAdapter 非 actor，依赖调用方隔离；event loop use-after-free 已修复（commit abda4ab） | FileBrowsing/Services/ThumbnailMPVAdapter.swift | P2 → P3 |
| P2-2 | ContentGridView shimmerOpacity 在 @State 而非 ContentGridView init 中初始化，导致首次 appear 才触发动画 | ContentGridView.swift:36 | P2 |
| P2-3 | `inferHDRType` 对 bt.1886 gamma 无显式匹配（走 SDR fallback），TestPlan 预期一致 | MPVPlayerAdapter.swift | P2 |
| P2-4 | VideoDetailView 798 行超过 SwiftLint file_length 限制（风格警告） | VideoDetailView.swift | P2 |

以上 P2 问题均来自 overnight review 记录，已在 ExecPlan 中标记为 fix phase 待处理。

---

## 7. 真机验证清单（需人类执行）

以下场景无法通过静态审计验证，需真机确认（基于 REGRESSION.md REG-128 ~ REG-132）：

1. **REG-128（P0）**: 播放视频中点击菜单 → 菜单稳定，子项可点击；快速连续点击 5 次无闪烁
2. **REG-129**: 播放 flat 视频 → Panorama 菜单项为 disabled 灰色；播放全景视频 → 三种模式均可点
3. **REG-130**: 播放 HDR10 内容 → 菜单显示 "HDR10" Toggle；SDR 内容 → 无 Toggle
4. **REG-131**: 二次进入视频列表 → 缩略图无闪烁（内存缓存命中）；快速滚动不卡顿
5. **REG-132**: 切换 WebDAV 数据源 → 立即看到骨架屏，旧内容消失

---

---

## 8. QA 执行附记（2026-04-06 Standard 档位复核）

本次执行由 Overnight Agent 发起，对已存在报告进行代码路径逐项复核验证：

| 验证项 | 方式 | 结论 |
|--------|------|------|
| StereoMode 全局无残留 | grep XrPlayer/ 全目录 | PASS（0 命中） |
| video-params/hdr-format 无调用 | grep XrPlayer/ | PASS（0 命中） |
| DecidePlaybackModeUseCase 约束矩阵代码 | 逐行代码读取 | PASS — flat 内容走 `[.window, .immersive]` 路径，SBS/TB 走 `.immersive` |
| ProjectionType 4-case + isPanoramic | ProjectionType.swift 代码读取 | PASS |
| gamma 决策树（pq→hdr10, hlg→hlg） | MPVPlayerAdapter:1316,1326 | PASS |
| accessibilityIdentifier PlayerControlsView | 代码读取 | PASS — 10 项全部具备 |
| VideoDetailView 返回按钮 + HDR Toggle 条件 + playbackModePicker | VideoDetailView 代码读取 | PASS |
| ContentGridView isLoading → skeletonGrid | ContentGridView:17-18 | PASS |
| FileBrowsingViewModel connectToDataSource 立即 files=[] + isLoading=true | FileBrowsingViewModel:141-142 | PASS |
| ThumbnailService 两级缓存 + inFlightTasks 去重 + 并发限流 | ThumbnailService.swift | PASS |
| ThumbnailMPVAdapter event loop use-after-free | 已修复，commit abda4ab | 修复已验证 |

**额外修复（本次 QA 期间）**: 提交 `abda4ab` — ThumbnailMPVAdapter event loop safe teardown（cleanup() 等待 event loop drain 再销毁 mpv handle，防止 use-after-free）。

**验收结论**: PASS（Standard 档位，所有严重/高/中等级别项通过；4 个 P2 noted 不影响判定）
