# Enchron 测试策略


## 双轨验证体系

本项目的验证分为两条独立轨道。visionOS 项目的特殊性在于：大多数有意义的 UI 验证只能在真机上完成。这不是缺陷，而是现实。测试策略的核心是最大化 agent 可自检范围，同时标准化人类真机验证流程。

每次代码改动必须在两条轨道上都有覆盖。


### 第一轨：Agent 可自检

每次改动后必须执行以下全部检查项。任何一项失败，agent 不可声称任务完成。

| 检查项 | 命令 | 工作目录 | 失败判定 |
|--------|------|---------|---------|
| 编译 | `swift build` | 仓库根目录 | 任何 error |
| 单元测试 | `swift test` | 仓库根目录 | 任何 failure |
| 架构守卫 | `swiftlint lint` | 仓库根目录 | error 级别违规 |
| WORKAROUND 规范 | `scripts/check-workaround.sh XrPlayer/` | 仓库根目录 | 任何未标注移除条件的 WORKAROUND |
| 契约验证 | 核对 `docs/contracts/` 是否与本次实现一致 | 仓库根目录 | 契约文档、OpenAPI 参考或 examples 与实现失配（仅在涉及远程数据流时） |
| 回归关联 | 匹配 `git diff --name-only` vs REGRESSION.md 代码路径映射索引 | — | 产出人类验证清单 |


### 第二轨：人类真机验证

visionOS 的 UI 流畅度、视觉效果、真机交互无法通过自动化测试验证。agent 必须根据 REGRESSION.md 的代码路径映射，生成标准化的人类验证清单交给用户在真机上执行。

人类验证清单格式：

    ## 人类真机验证清单

    本次改动文件：{git diff --name-only 的输出}
    匹配的回归项：{REG-编号列表}

    ### REG-001: 本地视频首播出画出声
    - [ ] 打开本地 MP4 文件
    - [ ] 2 秒内出画出声
    - [ ] 播放状态显示为 Playing

    ### REG-013: 播放控件面板不卡顿
    - [ ] 首次启动后打开"i"面板
    - [ ] 无明显卡顿（<1 秒）

    验证结果：通过 / 未通过 / 未测试（请标注）


## 可选轨：Agent 驱动的交互式 smoke

这不是默认验证轨道，而是一个可选的辅助机制。

它的目标不是替代真机验证，而是让 Agent 在用户明确要求时，可以通过 macOS 上的模拟器或桌面自动化方式，执行接近人类操作顺序的 smoke 检查，例如：

- 启动 app
- 打开某个页面或面板
- 点击播放控件
- 拖动进度条
- 打开播放列表并切换视频

适用规则：

- 默认不开启
- 只有用户显式要求“请用模拟器 / 桌面自动化做一轮 Agent 自检”时才执行
- 结果只能表述为“Agent 交互式 smoke 通过 / 失败”，不能表述为“已替代真机验证”
- 对 visionOS 来说，这一轨只能作为 UI 流程辅助验证，不能证明真机观感、空间交互、性能体感或 HDR 视觉正确性

建议使用场景：

- 回归项涉及明显的 UI 操作路径，但缺少对应的自动化单元测试
- 需要快速确认“按钮可点、页面能开、流程能走通”
- 用户明确希望 Agent 先做一轮模拟人类操作的预检

不适用场景：

- 需要判断真机空间交互体验
- 需要判断流畅度、沉浸感、视觉质量
- 需要判断 HDR / SDR 的肉眼观感是否正确


## 测试金字塔


### 底层：纯逻辑单元测试

不依赖 visionOS SDK、不需要模拟器或真机。`swift test` 即可执行。覆盖 Domain 层的业务规则和纯计算逻辑。

当前测试文件（Tests/XrPlayerCoreTests/）：

- DetailedTimelineGeometryTests.swift — 二级进度条几何计算（数据驱动，覆盖充分）
- CoreLogicTests.swift — FileFilter、LocalDataSourceAdapter、ProjectionType 分类、PlaybackSpeed/Position 边界
- V02Tests.swift — Domain 值对象（MediaProfile、PlaybackSpeed、PlaybackPosition、AudioTrack/SubtitleTrack）、DisambiguateGestureUseCase 状态机
- V03Tests.swift — 远程浏览适配器（SMB/WebDAV）、KeychainStore、CredentialSourceID、DataSource/ConnectionInfo Codable
- V04Tests.swift — MPVConfiguration 选项生成、PlaybackControlling Mock 流程、HDR 配置安全、VideoToolboxBridge
- PlaybackTimeFormatterTests.swift — 时间标签格式化器

应持续扩展的测试方向：

- CAEDRMetadata 设置逻辑：详见下方"HDR 测试设计"章节
- 投影类型检测逻辑：详见下方"全景测试设计"章节
- PlaybackMode 决策逻辑：全景/沉浸/窗口三分支的组合测试（全景格式 + 场景活跃、非全景 + 场景不活跃等）
- SortCriteria 排序正确性：按名称/时间/大小 x 升序/降序的全组合
- FileFilter 过滤规则：可播放格式列表的边界情况
- GestureDisambiguator 状态机转换：200ms 窗口内各种输入序列的状态变迁

测试命名规范：test + {被测行为} + {条件} + {预期结果}

例：`testMinimumZoomKeepsTimelineAtHalfViewportWidth`

优先使用数据驱动测试（输入数据 + 预期结果的表格），而不是为每种情况写独立的测试方法。这使得添加新的边界条件只需要加一行数据，而不是写一个新方法。


### 中层：编译期结构检查

通过 SwiftLint 自定义规则和脚本在编译时或手动运行时强制执行架构约束。

已实现的守卫：

| 守卫 | 实现方式 | 执行时机 | 对应门禁 |
|------|---------|---------|---------|
| Domain 层 import 限制 | SwiftLint `domain_no_ui_framework` | 每次编译 | G17 |
| Domain 层禁 try! | SwiftLint `no_force_try_in_domain` | 每次编译 | G17 |
| WORKAROUND 注释规范 | `scripts/check-workaround.sh` | 手动/CI | G18 |
| OpenAPI / 契约一致性 | 手动核对 `docs/contracts/` | 手动/CI | G13 |


### 顶层：真机验证

由人类在 Apple Vision Pro 真机上执行，按 REGRESSION.md 中的回归项驱动。真机验证不是"可选的补充"，是验证体系的核心组成部分。回归集（REGRESSION.md）是连接两条轨道的桥梁——它告诉 agent "改了这里就需要人类检查那里"。


## HDR 测试设计

HDR 测试分为三个层次：纯逻辑单元测试（agent 可执行）、配置一致性测试（agent 可执行）、真机视觉验证（人类执行）。

### 纯逻辑：CAEDRMetadata 选择逻辑

测试 `applyEDRMetadataToLayer()` 中根据 HDR 类型选择正确 EDR metadata 的逻辑。这部分可以通过提取纯函数来测试，不需要真实的 CAMetalLayer。

数据驱动测试表：

| HDR 类型 | sig-peak | 预期 metadata 类型 | 预期 maxLuminance | 预期 opticalOutputScale |
|---------|----------|-------------------|------------------|----------------------|
| sdr | nil | nil | — | — |
| hdr10 | 5.0 | hdr10 | 1015.0 (5.0 * 203) | 100.0 |
| hdr10 | nil/1.0 | hdr10 | 203.0 (1.0 * 203) | 100.0 |
| hdr10Plus | 10.0 | hdr10 | 2030.0 | 100.0 |
| dolbyVision | 5.0 | hdr10 | 1015.0 | 100.0 |
| hlg | any | hlg | — | — |

关键边界条件：
- sig-peak 为 nil 时应默认 1.0（reference white = 203 nits）
- DoVI 使用 hdr10 metadata（Apple 没有公开 DoVI CAEDRMetadata API）
- SDR 内容必须设置 `edrMetadata = nil`
- `CAEDRMetadata.isAvailable` 为 false 时不崩溃

### 纯逻辑：HDR 开关同步

测试 `setHDREnabled(_:)` 是否正确同步 edrMetadata 状态：

- `setHDREnabled(false)` → edrMetadata 被清除为 nil
- `setHDREnabled(true)` → edrMetadata 根据当前媒体 HDR 类型重新设置
- 切换 SDR 内容后再切换 HDR 内容 → edrMetadata 从 nil 变为有效值

### 配置一致性：MPVConfiguration HDR 选项

已有测试覆盖（V04Tests.swift）：
- `testHDRRuntimeCommandsRestoreAutoTRCAndPrimaries`
- `testSDRRuntimeCommandsForcesBT709`
- `testHDRAndSDRCommandsAreSymmetric`
- `testHDRDefaultsUseAutoTargetColorspaceHint`
- `testHDRRuntimeCommandsDoNotMutateTargetColorspaceHint`

需补充的测试：
- hdrRuntimeCommands 不应包含 tone-mapping 相关覆盖（gpu-next 内部处理）
- panorama 配置下 `useNativeGPUOutput = false` 时 HDR 选项不应包含 fbo-format

### 真机视觉验证

HDR 视觉正确性无法通过自动化测试验证。以下项目通过 REGRESSION.md 驱动人类真机验证：

- HDR10 视频：高光区域比 SDR 视频明显更亮（需 HDR 显示器或 AVP）
- HLG 视频：色彩自然，不过曝
- DoVI 视频：与 HDR10 类似的亮度表现
- SDR 视频：不受 HDR 逻辑影响，edrMetadata = nil
- HDR on/off 切换：视觉差异可感知（HDR on 时高光更亮）


## 全景测试设计

### 纯逻辑：投影类型检测

测试 `detectProjectionType()` 从 libmpv metadata 推断投影类型的逻辑。可通过提取纯函数测试。

数据驱动测试表：

| stereo3d-in | GSpherical:Spherical | GSpherical:ProjectionType | 预期 ProjectionType |
|-------------|---------------------|--------------------------|-------------------|
| "" | nil | nil | .flat |
| "sbs2l" | nil | nil | .stereoscopicSBS |
| "ab2t" | nil | nil | .stereoscopicOU |
| "" | "true" | "equirectangular" | .panorama360 |
| "" | "true" | "equirectangular" (hfov<=180) | .panorama180 |
| "" | nil | nil (普通 16:9) | .flat |
| "" | nil | nil (2:1 无标记) | .flat（不自动猜测） |

关键边界条件：
- 无元数据的普通视频必须返回 .flat
- 2:1 长宽比但无球形元数据标记的视频不应自动判定为全景
- 立体模式检测优先于球形元数据检测

### 纯逻辑：PanoramaSphereEntity 配置

- panorama360 时球体 scale.x < 0（法线翻转，用户在球内看）
- panorama180 时球体方向正确
- 球体半径为 10.0

### 真机验证

全景渲染的视觉正确性只能在 AVP 真机上验证（见 REGRESSION.md）。


## Agent 完成任务时必须产出的四件交付物

1. 代码变更（git diff 可审阅）
2. Agent 自检报告：

       ## Agent 自检报告
       - [x] swift build: 通过
       - [x] swift test: 通过（X 个测试）
       - [x] swiftlint lint: 无 error
       - [x] check-workaround.sh: 通过
       - [x] 回归项关联检查: 涉及 REG-001, REG-013
       - [ ] Agent 交互式 smoke: 未执行 / 通过 / 失败（仅在用户显式要求时填写）

3. 人类真机验证清单（从 REGRESSION.md 代码路径映射匹配生成）
4. 回归集更新（如果修复了 bug，必须在 REGRESSION.md 新增对应回归项）


## Agent 自检 Checklist

agent 提交改动前逐项回答。任何一项"否"且无合理理由，不可提交。

| 检查项 | 回答 |
|--------|------|
| 编译通过？ | 是/否 |
| 所有测试通过？ | 是/否 |
| 本次改动是否新增了测试？ | 是/否/不需要（理由） |
| SwiftLint 通过？ | 是/否 |
| 改动触发了哪些回归项？ | REG-{编号列表} |
| 是否修改了模块间接口？ARCHITECTURE.md 是否已更新？ | 是/否 |
| 是否引入了 WORKAROUND？是否标注了移除条件？ | 是/否 |
| 是否可能影响冷启动性能？ | 是/否/不确定 |
| 是否与沉浸场景未来兼容？ | 是/否/不适用 |
