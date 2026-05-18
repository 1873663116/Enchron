---
title: QA-Plan-First 方法论：visionOS Overnight 全覆盖质量驱动迭代
date: "2026-04-02"
category: docs/solutions/best-practices
module: overnight-autonomous-loop
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - "运行 visionOS 项目的自主 overnight AI 开发循环"
  - "决定是否在实现冲刺之前先设计 QA 路径"
  - "代码结构评分高（>95%）但用户可感知功能质量未知"
  - "验证无法通过单元测试自动化的空间/沉浸功能"
  - "为全景/立体视频生成测试素材"
tags:
  - qa-plan-first
  - overnight
  - visionos
  - immersive-space
  - health-score
  - e2e-qa
  - mpv
  - swiftui-state-polling
  - adversarial-review
  - test-material-metadata
---

# QA-Plan-First 方法论：visionOS Overnight 全覆盖质量驱动迭代

## 背景

Enchron visionOS overnight v2（15 轮）结束时报告代码健康度 97.75、13/13 终止条件全绿，看似已接近完成。但 v3 在正式修复代码前先设计了 59 条 E2E QA 路径并执行，发现用户可感知健康度只有 **70.7%**（34 PASS / 14 PARTIAL / 10 FAIL）。

这一落差来源于两种不同的"完成"定义：

- **代码健康度（97.75）**：逻辑在受控输入下计算正确（单元/集成测试通过）
- **用户健康度（70.7）**：从 UI 手势到 UseCase 到 Domain 到 UI 更新的完整链路在真实 App 中实际触发

v3 采用 QA-Plan-First 模式修复真实缺陷后，最终健康度达到 **95.69%**。

---

## 指导原则

### A. QA-Plan-First 模式

**在任何实现冲刺之前，先设计覆盖全部用户可感知功能的 E2E QA 路径，并对现有代码执行，建立真实基线。**

执行步骤：
1. 从用户视角枚举全部可感知功能（不是代码路径，而是"用户能看到/触摸到/感受到的东西"）
2. 为每个功能设计端到端路径，模拟真实操作序列（启动 App → 浏览文件 → 选视频 → 播放 → 控件交互）
3. 每条路径必须含**具体预期结果**（不接受"检查是否正常"）
4. 对当前代码运行所有路径，记录 PASS / PARTIAL / FAIL
5. 用此结果作为健康度基线，只修复真实 FAIL/PARTIAL 项
6. 修复后重跑同一路径集确认提升

**对抗性审查 QA 计划本身**（三阶段裁决）：
- 阶段 1（Codex/挑战者）：找出 QA 路径中的遗漏、过宽的断言、未覆盖的边界条件
- 阶段 2（Counter-Agent）：驳回 Simulator 无法测试的项目，保留核心功能挑战
- 阶段 3（Supervisor 裁决）：对照 Requirements.md 做最终决定

---

### B. 代码健康度 ≠ 用户健康度

在 Clean Architecture / DDD 项目中，每层隔离测试不能保证完整链路正常工作。

**已知会产生"断联但有测试"状态的模式**：

| 断联类型 | 症状 | 案例（Enchron） |
|---------|------|----------------|
| UseCase 存在但 UI 不调用 | 功能按钮触发无反应 | `SceneSelectorView` 未调用 `openImmersiveSpace()` |
| 状态已发出但 UI 无分支消费 | 指示器永不出现 | `.buffering` 有 ViewModel 状态但 `MainView` 无分支 |
| 后端方法存在但无 UI 入口 | 设置项存在但无法操作 | `setHDREnabled()` 存在，PlaybackMenuView 无 Toggle |
| 类存在于架构但未在 DI 实例化 | 功能静默失效 | `NetworkMonitor` 未在 `App/` 中注入 |

**检查清单**（每次实现新功能后）：
1. UI 组件是否真正调用了 UseCase 方法（不只是 UseCase 方法存在）
2. Adapter 发出的状态变化是否被 ViewModel 观察
3. ViewModel 的状态变化是否被 View 渲染为可见内容

---

### C. 空间/全景视频测试素材的元数据验证

`ffprobe` 的编解码/分辨率/容器验证对空间视频**不充分**。必须额外验证 GSpherical 投影元数据。

**验证命令**：
```bash
# 验证是否有球形视频元数据
ffprobe -v error -show_frames -select_streams v:0 <file> | grep "Side data"
# 期望输出：Side data: spherical video
```

若输出为空，文件缺乏 GSpherical 元数据，播放器将检测为平面窗口模式。

**完整测试素材生成流程**：
```bash
# Step 1: ffmpeg 生成基础文件
ffmpeg -f lavfi -i testsrc=size=3840x1920 -t 5 -vcodec libx264 test_360_raw.mp4

# Step 2: 验证编解码/分辨率（现有步骤）
ffprobe -v quiet -show_streams -select_streams v:0 test_360_raw.mp4 | grep -E "codec|width|height"

# Step 3: 新增 — 验证球形元数据
ffprobe -v error -show_frames -select_streams v:0 test_360_raw.mp4 | grep "Side data"
# 如果为空，继续 Step 4

# Step 4: 注入 GSpherical 元数据
python3 spatial-media/spatialmedia -i --stereo=none test_360_raw.mp4 test_360.mp4

# Step 5: 验证注入结果
ffprobe -v error -show_frames -select_streams v:0 test_360.mp4 | grep "Side data"
# 期望：Side data: spherical video
```

**受影响格式**：所有宣称支持的全景/立体格式均需此验证：
- 360° 等距矩形（equirectangular）
- 180° VR（半球）
- SBS 左右格式立体
- OU 上下格式立体
- 鱼眼投影（fisheye）

---

### D. visionOS ImmersiveSpace 沉浸级别切换的正确模式

`.immersionStyle(selection:in:)` modifier 必须应用在 `@main App` struct 中的 `ImmersiveSpace` **Scene 声明上**，而非任何 View 或 ViewModel 内部。

参考：Apple 官方 HelloWorld 示例 `World/WorldApp.swift`。

**正确模式**：
```swift
@main
struct EnchronApp: App {
    @State private var immersionStyle: ImmersionStyle = .mixed

    var body: some Scene {
        ImmersiveSpace(id: "MainImmersiveSpace") {
            ImmersiveSpaceView()
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full) // Scene 层
        .onChange(of: appModel.isFullImmersion) { _, full in
            immersionStyle = full ? .full : .mixed
        }
    }
}
```

**禁止做法**：
```swift
// ❌ 错误：在 View 内部应用，无效
struct ImmersiveSpaceView: View {
    @State var style: ImmersionStyle = .mixed
    var body: some View {
        RealityView { ... }
            .immersionStyle(selection: $style, in: .mixed, .full) // 被忽略
    }
}
```

修改 `immersionStyle` 状态变量会**立即**改变沉浸级别，无需关闭再重新打开 ImmersiveSpace。

---

### E. mpv + SwiftUI 状态传播模式（200ms 轮询架构）

mpv 在 C 线程上运行并异步调用 Swift 回调。正确的线程架构：

```
mpv C thread
    ↓ mpv event callback
MPVPlayerAdapter.updateState()
    ↓ stateQueue.sync { internalState = newState }
WindowVideoViewModel (200ms Timer on MainActor)
    ↓ self.playbackState = player.currentState
View (SwiftUI)
    ↓ switch playbackState { case .buffering: ProgressView() }
```

**新增 PlaybackState case 的完整检查单**：
1. 在 MPVPlayerAdapter 注册对应 mpv 属性的观察：`mpv_observe_property(mpv, 0, "property-name", MPV_FORMAT_FLAG)`
2. 在 `handlePropertyChange()` 中更新 `internalState`
3. 确认 `WindowVideoViewModel` 轮询读取 `player.currentState`（已有 200ms 轮询，无需修改）
4. 在相关 View（`MainView.swift` 或 PlayerUI）中添加 UI 分支消费该状态
5. 添加单元测试：mock adapter 发出新状态 → 断言 ViewModel 传播

**典型失败案例（缓冲指示器）**：
```
❌ 原状态：Step 1 缺失（paused-for-cache 未注册）
   → MPVAdapter 从不发出 .buffering
   → MainView 的 .buffering 分支永不触发
   → 轮询架构正确，UI 分支正确，但 Step 1 空缺导致全链路静默失效
```

---

## 为何重要

1. **QA-Plan-First** 将虚假的代码健康度（97.75%）暴露为真实的用户健康度（70.7%），避免以错误信心发布
2. **断联检查** 防止 Clean Architecture 的层隔离产生"通过测试的幽灵代码"——看似实现但实际上无法被用户触达
3. **GSpherical 元数据验证** 防止全景检测测试套件在没有正确 GSpherical metadata 的情况下通过（产生假阴性：视频看起来格式正确，但播放器静默降级为窗口模式）
4. **ImmersiveSpace 正确绑定层** 避免切换沉浸级别无效，或因反复调用 `openImmersiveSpace()` 产生状态失步
5. **mpv 状态传播检查单** 防止任何一层缺失导致状态变化静默丢失（尤其是由 mock 测试掩盖的断联）

---

## 适用场景

- overnight 自主开发循环开始前（PLANNING 阶段）
- 任何功能完整里程碑的 Release Review 前
- 编写覆盖空间/全景/立体内容的测试素材时
- 添加新的 `PlaybackState` case 或 mpv 属性观察时
- 添加涉及 `ImmersiveSpace` 的沉浸级别切换 PR 时
- agent 驱动的批量实现冲刺后（agent 往往同步写代码和测试）

---

## 示例

### 完整 QA 路径样本（不可接受 vs 可接受）

```
❌ 不可接受：
路径 D01：进入沉浸影院模式，检查是否正常

✅ 可接受：
路径 D01：进入沉浸影院模式
  操作序列：启动 App → 选择本地视频（SDR-test.mkv）→ 点击 Video Detail 中的"Open in Immersive Cinema"
  预期结果：ImmersiveSpace 打开，虚拟屏幕可见，视频画面出现在虚拟屏幕上，播放控件显示在 Ornament 中
  实际结果（Round 10）：FAIL — 虚拟屏幕可见但无视频画面（VirtualScreenEntity.textureResource 为 nil）
  根因：PlayerControlsView.attachVideoLayer() 仅在 mode == .panorama 时调用，.immersive 分支缺失
```

### 代码健康度 vs 用户健康度对比

```
overnight v2 结束时：
  代码健康度：97.75（248 单元测试全绿）
  用户健康度：未知（从未系统性执行 E2E 路径）

overnight v3 开始时（QA-Plan-First 基线）：
  执行 59 条 E2E 路径后：
  PASS: 34 / PARTIAL: 14 / FAIL: 10
  用户健康度基线：70.7%

overnight v3 修复后（目标 ≥95%）：
  PASS: 54 / PARTIAL: 3 / FAIL: 1（M04 WorldTracking，P2降级）
  用户健康度：95.69%
```

---

## 相关

- [`docs/solutions/best-practices/overnight-test-first-adversarial-iteration-visionos-2026-04-02.md`](overnight-test-first-adversarial-iteration-visionos-2026-04-02.md) — 本方法论的具体执行记录（v2 overnight，健康度 97.75，test-first 对抗性迭代）
- [`docs/solutions/best-practices/autonomous-overnight-visionos-architectural-patterns.md`](autonomous-overnight-visionos-architectural-patterns.md) — ImmersiveSpace 全局入口模式（Pattern 7）和结构化 QA 模式（Pattern 8）
- [`docs/solutions/best-practices/overnight-premature-exit-monitoring-and-correction-2026-04-02.md`](overnight-premature-exit-monitoring-and-correction-2026-04-02.md) — overnight 提前退出的监控与补救，与本文件的终止条件验证互补
