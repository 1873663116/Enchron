# QA Report: V2 Bug Fix Iteration — Static Analysis + Build Verification
**Date:** 2026-04-06  
**Branch:** MinimaxTest  
**Method:** xcodebuild 构建验证 + 静态代码分析（无 Simulator UI）  
**Scope:** §5.4-§5.11 共 8 Units，TestPlan A 类测试项 17 条  
**TestPlan:** docs/plans/active/TestPlan.md  
**VerifyList:** docs/plans/active/VerifyList.md  

---

## 构建结果

```
xcodebuild -project XrPlayer.xcodeproj -scheme XrPlayer -destination 'generic/platform=visionOS' build

** BUILD SUCCEEDED **
```

**Error 数量：0**  
**Warning：** SwiftLint trailing_comma（3 处，MPVPlayerAdapter.swift）+ nesting violation（2 处，StereoLayout/MediaProfile ValueObjects）— 均为 pre-existing，不影响功能。

---

## A 类测试项逐条结果

### Unit 1 — §5.4 播放中菜单闪烁与交互修复

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **1.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |

### Unit 2 — §5.5 HDR 视频详情页超时防卡死

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **2.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **2.2 超时逻辑** | **PASS** | `PlaybackLaunchCoordinator.swift:250`：`let maxWaitMs = 3000`，poll loop 到 3000ms 退出，返回 fallback profile（`PreparedPlayback.isMetadataPartial = true`）；`MediaProfilePrefetchService.swift:19`：`timeoutSeconds = .seconds(3)` 同步配置 |

### Unit 3 — §5.6 文件夹级别元数据预读 + 缓存

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **3.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **3.2 缓存命中逻辑** | **PASS** | `MediaProfilePrefetchService.swift:91-96`：先查 `metadataService.cachedProfile(for:)`，有结果则直接写入 sessionCache 并 return，不触发 AVFoundation 检测 |
| **3.3 缓存失效逻辑** | **PASS** | `MediaProfilePrefetchService.swift:58-61`：sessionCache 以 `(fileIdentifier, modifiedAt)` 为 key；modifiedAt 变化时 miss，重新调用 `detectProfile` |
| **3.4 并发限制** | **PASS** | `MediaProfilePrefetchService.swift:51-83`：`withTaskGroup` 内 `running` 计数器控制；`running >= Self.maxConcurrency (3)` 时等待 `group.next()` 再添加新任务，严格保持 ≤3 并发 |
| **3.10 单文件超时跳过** | **PASS** | `prefetchOne` 用 `withThrowingTaskGroup` 竞速：检测 task vs 3s sleep task；CancellationError 在 catch 块中静默处理（`print("[Prefetch] timeout/cancelled ...")`），不会中断外层 `runBatch` 的 for 循环 |

### Unit 4 — §5.9 沉浸空间四项子问题修复

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **4.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **4.2 结构守卫** | **PASS** | Grep 全仓库 `openImmersiveSpace`：**唯一调用文件为 `MainView.swift`**，且仅在 `openImmersiveSpaceUnified()` 内（`MainView.swift:306`）调用。`MainView.swift:261` 注释明确标注："that cannot call openImmersiveSpace directly per Architecture Invariant"。SceneSelectorView、ToggleImmersiveSpaceButton 均通过 `appModel.immersiveSpaceRequest` 路由。 |

### Unit 5 — §5.10 播放控件严格对齐 player.html

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **5.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **5.2 控制栏按钮顺序** | **PASS** | `PlayerControlsView.swift:88-165`：HStack 顺序 `leftMenu` → Rewind(gobackward.10) → Play/Pause → Forward(goforward.10) → `NLETimelineToggleButton` → `rightMenu`，即 Menu → Rew → Play → Fwd → NLE → Settings，共 6 个，与 player.html 一致 |
| **5.3 进度条布局** | **PASS** | `SeekBarView`（`PlayerControlsView.swift:503-545`）：左侧 `Text(currentTime)` → 中间 `Slider` → 右侧 `Text(remainingTimeLabel)`，与 TestPlan 规格"左侧当前时间、右侧剩余时间、中间滑块"完全匹配 |

### Unit 6 — §5.7 文件浏览性能与交互修复

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **6.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **6.2 skeleton shimmer 可见** | **PASS** | `ContentGridView.swift:36-61`：`@State shimmerOpacity: Double = 0.4`，`.onAppear { shimmerOpacity = 0.9 }`，动画 `.easeInOut(duration: 1.0).repeatForever(autoreverses: true)`。`.id(isLoading)` 确保数据源切换时动画重置。`SkeletonCardView` 使用 `redacted(reason: .placeholder)` 呈现 shimmer 效果，结构正确 |

### Unit 7 — §5.11 NLE 二级时间轴关闭动效修复

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **7.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **7.2 transition 方向** | **PASS** | `NLETimelineView.swift:56`：`.transition(.opacity.combined(with: .move(edge: .bottom)))`，edge 为 `.bottom`，符合 TestPlan 要求 |

### Unit 8 — §5.8 视频画布跟随窗口缩放

| 项目 | 结果 | 验证依据 |
|------|------|----------|
| **8.1 编译通过** | **PASS** | BUILD SUCCEEDED，零 error |
| **8.2 containerSize 传递** | **PASS** | `MainView.swift:45-49`：`GeometryReader { geometry in WindowVideoView(viewModel:, containerSize: geometry.size) }`；`WindowVideoView.updateUIView:57-68`：`containerSize != .zero` 时 `nativeView.frame = CGRect(origin: .zero, size: containerSize)`，并调用 `setNeedsLayout()/layoutIfNeeded()`，window resize 触发 frame 更新 |

---

## A 类测试项汇总

| # | 测试项 | 结果 |
|---|--------|------|
| 1.1 | Unit 1 编译 | PASS |
| 2.1 | Unit 2 编译 | PASS |
| 2.2 | 超时 3s 逻辑 | PASS |
| 3.1 | Unit 3 编译 | PASS |
| 3.2 | 缓存命中 | PASS |
| 3.3 | 缓存失效 | PASS |
| 3.4 | 并发限制 ≤3 | PASS |
| 3.10 | 单文件超时跳过 | PASS |
| 4.1 | Unit 4 编译 | PASS |
| 4.2 | 结构守卫 openImmersiveSpace | PASS |
| 5.1 | Unit 5 编译 | PASS |
| 5.2 | 控制栏顺序 | PASS |
| 5.3 | 进度条布局 | PASS |
| 6.1 | Unit 6 编译 | PASS |
| 6.2 | skeleton shimmer | PASS |
| 7.1 | Unit 7 编译 | PASS |
| 7.2 | transition .bottom | PASS |
| 8.1 | Unit 8 编译 | PASS |
| 8.2 | containerSize 传递 | PASS |

**总计：19/19 PASS（含 8 个编译项 + 11 个结构/逻辑分析项）**

---

## VerifyList 映射

本次验证覆盖的 VerifyList 条目：

**功能需求（代码层面可验证的）：**
- §5.5：之前导致卡死的 HDR 视频 → 最多 3 秒后 UI 可交互 ✓（maxWaitMs = 3000）
- §5.6：缓存失效策略：文件修改时间变化时重新检测 ✓（sessionCache key 含 modifiedAt）
- §5.6：快速切换文件夹 → 旧预读 Task 被正确取消 ✓（activeBatchTask?.cancel()）
- §5.9a：所有进入沉浸空间的路径统一经过 PlaybackLaunchCoordinator ✓（结构守卫 PASS）
- §5.10：控制栏 pill 按钮数量和顺序 ✓
- §5.10：进度条布局 ✓
- §5.11：NLE 时间轴关闭时向底部滑入收起 ✓（.move(edge: .bottom)）
- §5.8：containerSize 变化触发 layout 更新 ✓

**边界与错误处理：**
- HDR 检测超时 → fallback 默认 profile ✓（isMetadataPartial flag + fallback SDR）
- 元数据预读单文件超时 → 跳过该文件，继续预读其他文件 ✓（CancellationError 静默处理）

---

## 升级项（搞不定的问题）

无。所有 A 类测试项全部 PASS。

H 类测试项（真机验证）共 48 条，需真机执行，本次不在范围内。

---

## 总状态

**PASS** — 19/19 A 类测试项全部通过，BUILD SUCCEEDED 零 error。
