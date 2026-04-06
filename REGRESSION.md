# Enchron 回归集

更新时间：2026-04-06


## 使用方式

1. Agent 改动代码前：检查本文件中"代码路径映射索引"，预判改动会触发哪些回归项
2. Agent 改动代码后：用 `git diff --name-only` 获取改动文件列表，与索引匹配，执行所有匹配的"agent 自检"项，列出所有匹配的"真机验证"项生成人类验证清单
3. Agent 修复 bug 后：必须在本文件新增对应的回归项（G14 强制要求）


## 代码路径映射索引

| 改动路径 | 关联回归项 |
|---------|-----------|
| PlaybackCore/Adapters/MPV/* | REG-001, REG-002, REG-015, REG-017, REG-018, REG-060, REG-061, REG-062, REG-063, REG-070 |
| PlaybackCore/Domain/* | REG-001, REG-002, REG-015, REG-017, REG-018 |
| PlaybackCore/UseCases/* | REG-001, REG-002, REG-015, REG-017, REG-018 |
| PlayerUI/UseCases/DetailedTimelineGeometry.swift | REG-080 |
| PlayerUI/Views/PlayerControlsView.swift | REG-012, REG-013, REG-015, REG-016, REG-018, REG-019, REG-080, REG-081, REG-108, REG-109, REG-110, REG-116, REG-117, REG-119, REG-120, REG-123, REG-124, REG-125, REG-128, REG-129, REG-130 |
| PlayerUI/Views/VideoDetailView.swift | REG-082, REG-088, REG-120 |
| PlayerUI/Views/PlayerControlSurface.swift | REG-012, REG-013, REG-015, REG-016, REG-019, REG-123 |
| PlayerUI/Views/PlaylistView.swift | REG-019 |
| PlayerUI/Views/PlaybackMenuView.swift | REG-018, REG-112, REG-120 |
| PlayerUI/Domain/* | REG-012, REG-015, REG-016 |
| FileBrowsing/Adapters/SMB/* | REG-020, REG-021, REG-023, REG-092 |
| FileBrowsing/Adapters/WebDAV/* | REG-022, REG-092 |
| FileBrowsing/Adapters/PhotoLibrary/* | REG-090, REG-096 |
| FileBrowsing/ViewModels/* | REG-019, REG-020, REG-021, REG-022, REG-023, REG-090, REG-092, REG-114, REG-132 |
| FileBrowsing/Domain/* | REG-020, REG-022 |
| FileBrowsing/Views/* | REG-020, REG-089, REG-090, REG-092, REG-131, REG-132 |
| FileBrowsing/Services/ThumbnailService.swift | REG-131 |
| FileBrowsing/Services/ThumbnailCache.swift | REG-131 |
| Persistence/Adapters/SwiftDataStore.swift | REG-030, REG-091 |
| Persistence/Adapters/UserDefaultsStore.swift | REG-031, REG-085, REG-115 |
| Persistence/Adapters/KeychainStore.swift | REG-021 |
| Persistence/Domain/* | REG-030, REG-031 |
| App/MainView.swift | REG-041, REG-111, REG-116, REG-117, REG-124, REG-126 |
| App/XrPlayerApp.swift | REG-091, REG-094 |
| App/PlaybackLaunching.swift | REG-095 |
| App/PlaybackLaunchCoordinator.swift | REG-001, REG-019, REG-040, REG-082, REG-083, REG-085, REG-086, REG-087, REG-093, REG-095, REG-109, REG-113 |
| App/NetworkMonitor.swift | REG-113 |
| App/PreparedPlayback.swift | REG-082, REG-083 |
| App/AppCoordinator.swift | REG-040, REG-041 |
| App/Navigation/* | REG-041, REG-084, REG-123 |
| WindowVideoView.swift | REG-126 |
| Shared/MPVNativeMetalLayerView.swift | REG-126 |
| SpatialScene/* | REG-050, REG-070, REG-071, REG-100, REG-101, REG-102, REG-103, REG-104, REG-105, REG-106, REG-107, REG-108, REG-109 |
| SpatialScene/Domain/* | REG-100, REG-101, REG-102, REG-103, REG-104, REG-105, REG-106, REG-107 |
| SpatialScene/Renderers/VirtualScreenEntity.swift | REG-100, REG-101, REG-121 |
| SpatialScene/Renderers/EnvironmentDomeEntity.swift | REG-104, REG-118 |
| SpatialScene/Renderers/PanoramaLayerBridge.swift | REG-070, REG-071, REG-106, REG-107 |
| SpatialScene/Renderers/PanoramaSphereEntity.swift | REG-070, REG-071, REG-105, REG-121 |
| SpatialScene/Renderers/* | REG-070, REG-071, REG-100, REG-101, REG-105, REG-106, REG-107 |
| SpatialScene/Scenes/ImmersiveSpaceView.swift | REG-070, REG-071, REG-100, REG-101, REG-104, REG-105, REG-106, REG-107, REG-109, REG-118, REG-121 |
| SpatialScene/Modifiers/DragRotationModifier.swift | REG-121 |
| SpatialScene/Views/SceneSelectorView.swift | REG-050, REG-104, REG-123 |
| PlayerUI/UseCases/DecidePlaybackModeUseCase.swift | REG-109, REG-125, REG-129 |
| PlayerUI/UseCases/DisambiguateGestureUseCase.swift | REG-117 |
| PlayerUI/Views/DetailedTimelineView.swift | REG-119 |
| PlayerUI/Views/NLETimelineView.swift | REG-123, REG-127 |
| PlayerUI/Views/TimelineRulerView.swift | REG-127 |
| PlayerUI/Views/ScreenPositionControlView.swift | REG-115, REG-120 |
| PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift | REG-001, REG-002, REG-015, REG-017, REG-018, REG-060, REG-061, REG-062, REG-063, REG-070, REG-111, REG-122, REG-130 |
| PlaybackCore/Domain/ValueObjects/StereoLayout.swift | REG-106 |
| Persistence/Domain/Entities/UserPreferences.swift | REG-115 |
| Settings/Views/SettingsView.swift | REG-031, REG-085, REG-101, REG-103, REG-104, REG-115 |
| Shared/VideoShaders.metal | REG-107 |

路径粒度说明：默认为目录级（如 `PlaybackCore/Domain/*`）。对于高风险的关键文件使用文件级（如 `PlaybackLaunchCoordinator.swift`）。


---


## PlaybackCore 回归项


### REG-001: 本地视频首播出画出声

- **来源**: v0.1 验收标准
- **触发条件**: 改动 PlaybackCore/、App/PlaybackLaunchCoordinator.swift
- **Agent 自检**: `swift build` 编译通过；`swift test` 全部通过
- **真机验证**: 冷启动应用 → 选择一个本地视频文件 → 2 秒内出画出声 → 播放状态显示为 Playing
- **退化信号**: 黑屏超过 2 秒、无声音、崩溃、播放状态卡在 Loading
- **状态**: active
- **创建日期**: 2026-03-14


### REG-002: 播放暂停恢复音画同步

- **来源**: v0.1 验收标准
- **触发条件**: 改动 PlaybackCore/、PlayerUI/Views/PlayerControlsView.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频中点暂停 → 画面冻结 → 点恢复 → 音画同步继续播放，无明显跳帧
- **退化信号**: 恢复后音画不同步（嘴型对不上声音）、画面卡住不动、恢复后重新从头播放
- **状态**: active
- **创建日期**: 2026-03-14

## PlayerUI 回归项


### REG-010: 二级进度条几何计算正确

- **来源**: G2 质量门禁
- **触发条件**: 改动 PlayerUI/UseCases/DetailedTimelineGeometry.swift 或 PlayerUI/Views/DetailedTimelineView.swift
- **Agent 自检**: `swift test --filter DetailedTimelineGeometry` 全部通过
- **真机验证**: 进入二级进度条 → 捏合缩放时间轴 → 时间刻度变化合理且无跳跃 → 拖动跟手
- **退化信号**: 时间轴显示异常、拖动不跟手、缩放后刻度消失或重叠
- **状态**: retired
- **退役日期**: 2026-04-02
- **退役原因**: DetailedTimelineView 已删除，二级进度条模式被统一时间轴替代（T3.3）。几何计算由 REG-080 覆盖。
- **创建日期**: 2026-03-14


### REG-011: 二级进度条进入退出流畅

- **来源**: G2 + G5 质量门禁
- **触发条件**: 改动 PlayerUI/Views/DetailedTimelineView.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 点击进度条区域 → 平滑切换到二级进度条模式 → 点击空白区域退出 → 恢复正常播放 UI，无残留元素
- **退化信号**: 切换时明显卡顿、退出后 UI 元素残留、进入/退出动画不平滑
- **状态**: retired
- **退役日期**: 2026-04-02
- **退役原因**: 二级进度条模式已删除，统一时间轴始终可见（T3.3），不存在进入退出切换。
- **创建日期**: 2026-03-14


### REG-012: 播放控件可见可操作

- **来源**: G3 质量门禁
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift 或 PlayerUI/Views/PlayerControlSurface.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频时 → 所有控件（播放/暂停/快进/倍速）可见 → hover 有视觉反馈 → 点击功能正常
- **退化信号**: 按钮消失或不可见、无 hover 反馈、点击无响应、控件层级混乱导致误触
- **状态**: active
- **创建日期**: 2026-03-14


### REG-013: 播放控件面板首次打开不卡顿

- **来源**: KI-007（冷启动卡顿）
- **触发条件**: 改动 PlayerUI/Views/* 或 PlayerUI/UseCases/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 冷启动应用 → 打开第一个视频 → 首次打开"i"信息面板 → 无明显卡顿（<1 秒）
- **退化信号**: 首次打开面板时可感知的卡顿（>1 秒）；后续打开正常（说明是冷启动初始化问题）
- **状态**: active
- **创建日期**: 2026-03-14


### REG-014: 二级进度条预览可命中首尾边界

- **来源**: 2026-03-14 详细时间轴预览 seek 边界节流修复
- **触发条件**: 改动 PlayerUI/Views/DetailedTimelineView.swift 或 PlayerUI/UseCases/DetailedTimelineGeometry.swift
- **Agent 自检**: `swift test --filter DetailedTimelinePreviewSeekPolicyTests` 全部通过
- **真机验证**: 进入二级进度条 → 拖动到最左侧边界时预览 seek 到 00:00 → 拖动到最右侧边界时预览 seek 到视频末尾帧
- **退化信号**: 到达首尾边界后仍停在边界前一小段、无法精确回到 00:00、末尾一小段无法命中
- **状态**: retired
- **退役日期**: 2026-04-02
- **退役原因**: DetailedTimelineView 已删除。统一时间轴使用标准 Slider，首尾边界由 Slider 原生行为保证。
- **创建日期**: 2026-03-14


### REG-015: 快进快退可用且步长正确

- **来源**: 播放控制基础可用性
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/Views/PlayerControlSurface.swift、PlaybackCore/*
- **Agent 自检**: `swift build` 编译通过；`swift test --filter V04Tests` 通过
- **真机验证**: 播放视频时点快退 10 秒 → 播放位置向前回退约 10 秒；再点快进 10 秒 → 播放位置向后前进约 10 秒；多次点击后位置仍合理
- **退化信号**: 步长错误、点击无响应、位置跳错方向、超出首尾边界后行为异常
- **状态**: active
- **创建日期**: 2026-03-14


### REG-016: 主进度条可拖动并正确 seek

- **来源**: 播放控制基础可用性
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/Views/PlayerControlSurface.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频时拖动主进度条到中段和尾段 → 松手后跳转到对应时间点 → 时间标签与实际播放位置一致
- **退化信号**: 进度条无法拖动、松手后不 seek、seek 到错误位置、时间标签不更新
- **状态**: active
- **创建日期**: 2026-03-14


### REG-017: 逐帧步进在详细时间轴中可用

- **来源**: 详细时间轴精确控制能力
- **触发条件**: 改动 PlayerUI/Views/DetailedTimelineView.swift、PlayerUI/UseCases/DetailedTimelineGeometry.swift、PlaybackCore/*
- **Agent 自检**: `swift build` 编译通过；`swift test --filter V04Tests` 通过
- **真机验证**: 进入二级进度条 → 点击前一帧 / 后一帧 → 画面逐帧移动，方向正确，不会直接跳成多秒 seek
- **退化信号**: 按钮无响应、方向反了、一次点击跨越多帧、退出二级进度条后控件残留异常
- **状态**: retired
- **退役日期**: 2026-04-02
- **退役原因**: 逐帧步进已移至 PlayerControlsView 的 secondaryControlRow（T3.3），由 REG-081 覆盖。
- **创建日期**: 2026-03-14


### REG-018: 音轨与字幕可切换且状态正确显示

- **来源**: 播放设置基础可用性
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/Views/PlaybackMenuView.swift、PlaybackCore/*
- **Agent 自检**: `swift build` 编译通过；`swift test --filter V04Tests` 通过
- **真机验证**: 播放包含多音轨和字幕的视频 → 切换音轨后声音来源变化且当前项显示正确；切换字幕开/关和不同字幕轨后画面与当前项显示一致
- **退化信号**: 菜单项显示错乱、切换后无效果、字幕无法关闭、当前选中状态与实际播放不一致
- **状态**: active
- **创建日期**: 2026-03-14


### REG-019: 播放中打开选集并切换视频正常

- **来源**: 播放中切片 / 切集可用性
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/Views/PlaylistView.swift、FileBrowsing/ViewModels/*、App/PlaybackLaunchCoordinator.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 正在播放视频时打开选集 / 播放列表 → 选择另一视频 → 当前视频正常停止，新视频正常开始，UI 不残留旧时长、旧媒体信息或旧播放状态
- **退化信号**: 切换后仍显示旧视频信息、旧视频未停止、新视频未启动、播放列表打开导致卡死或状态错乱
- **状态**: active
- **创建日期**: 2026-03-14


---


## FileBrowsing 回归项


### REG-020: SMB 连接与文件夹浏览

- **来源**: KI-011 + v0.3 验收标准 + RES-002
- **触发条件**: 改动 FileBrowsing/Adapters/SMB/*、FileBrowsing/ViewModels/*、FileBrowsing/Views/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 输入 SMB 服务器 IP → 连接成功 → 枚举显示可用 share → 选择 share 进入浏览 → 看到文件和文件夹列表 → 点击子文件夹可以展开
- **退化信号**: 连接失败、share 列表为空、子文件夹点击无反应（KI-011）、文件列表为空
- **状态**: active
- **创建日期**: 2026-03-14


### REG-021: SMB 凭证持久化稳定

- **来源**: RES-005（凭证 key 漂移修复）
- **触发条件**: 改动 FileBrowsing/Adapters/SMB/*、Persistence/Adapters/KeychainStore.swift
- **Agent 自检**: `swift build` 编译通过；grep 确认 SMB 凭证 key 使用 host 级稳定键
- **真机验证**: 添加 SMB 服务器并输入凭证 → 退出 app → 重新打开 → SMB 自动连接（不重新要求输入密码）
- **退化信号**: 重启后需要重新输入密码、连接时提示认证失败
- **状态**: active
- **创建日期**: 2026-03-14


### REG-022: WebDAV 浏览与播放

- **来源**: v0.3 验收标准
- **触发条件**: 改动 FileBrowsing/Adapters/WebDAV/*、FileBrowsing/ViewModels/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 添加 WebDAV 服务器 → 连接成功 → 浏览文件夹结构 → 选择视频文件 → 播放正常
- **退化信号**: 连接失败、文件列表为空、选择文件后无法播放
- **状态**: active
- **创建日期**: 2026-03-14


### REG-023: SMB 子目录中的视频可播放

- **来源**: KI-011 修复后的路径语义收口
- **触发条件**: 改动 FileBrowsing/Adapters/SMB/*、FileBrowsing/ViewModels/*
- **Agent 自检**: `swift build` 编译通过；`swift test --filter SMBDataSourceAdapterTests` 通过
- **真机验证**: 连接 SMB → 进入某个子目录 → 选择该子目录中的视频文件 → 正常播放，且路径不回退到 share 根目录
- **退化信号**: 子目录能打开但播放 URL 指向 share 根、点击子目录文件后打开了错误视频、子目录文件无法播放
- **状态**: active
- **创建日期**: 2026-03-15


---


## Persistence 回归项


### REG-030: 播放进度保存与恢复

- **来源**: RES-003（Persistence adapter 实现）
- **触发条件**: 改动 Persistence/Adapters/SwiftDataStore.swift、Persistence/Domain/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频到某个位置（如 5 分钟处）→ 退出 app → 重新打开 → 选择同一视频 → 提示恢复进度或自动恢复到之前位置
- **退化信号**: 进度丢失（从头播放）、恢复位置严重偏差（偏差 >10 秒）
- **状态**: active
- **创建日期**: 2026-03-14


### REG-031: 用户设置持久化

- **来源**: RES-003（Persistence adapter 实现）
- **触发条件**: 改动 Persistence/Adapters/UserDefaultsStore.swift、Persistence/Domain/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 修改某个设置项（如默认倍速）→ 退出 app → 重新打开 → 设置保持修改后的值
- **退化信号**: 设置重置为默认值
- **状态**: active
- **创建日期**: 2026-03-14


---


## App 层回归项


### REG-040: 播放启动路径统一

- **来源**: RES-001（启动路径分叉修复）
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、App/AppCoordinator.swift
- **Agent 自检**: grep 检查确认所有播放启动代码路径都经过 PlaybackLaunchCoordinator
- **真机验证**: 从文件浏览器选择文件 → 播放正常；从播放列表选择文件 → 播放正常；两条路径的启动行为一致
- **退化信号**: 某条路径启动失败后 UI 仍停留在"正在播放"状态（RES-001 原始问题）
- **状态**: active
- **创建日期**: 2026-03-14


### REG-041: 标签栏导航正常

- **来源**: v0.1 基本功能
- **触发条件**: 改动 App/MainView.swift、App/Navigation/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 文件浏览标签 → 内容正常加载；场景选择标签 → 列表正常显示；设置标签 → 设置页正常
- **退化信号**: 标签页消失、切换后内容为空白、切换导致崩溃
- **状态**: active
- **创建日期**: 2026-03-14


---


## SpatialScene 回归项


### REG-050: 场景选择页正常显示

- **来源**: v0.4 基础功能
- **触发条件**: 改动 SpatialScene/* 目录下任何文件
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 切换到场景选择标签 → 可用场景列表正常显示 → 无崩溃
- **退化信号**: 列表为空、崩溃、场景卡片显示异常
- **状态**: active
- **创建日期**: 2026-03-14


---


## HDR EDR Metadata 回归项


### REG-060: HDR10 内容设置正确的 CAEDRMetadata

- **来源**: KI-010 修复（CAEDRMetadata 缺失）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift
- **Agent 自检**: `swift build` 编译通过；`swift test` 中 EDR metadata 选择逻辑测试通过
- **真机验证**: 播放 HDR10 视频 → 高光区域比 SDR 视频明显更亮 → 日志显示 edrMetadata 已设置且 maxLuminance > 203
- **退化信号**: HDR10 视频高光被压平、edrMetadata 为 nil、maxLuminance 计算错误
- **状态**: active
- **创建日期**: 2026-03-17


### REG-061: HLG 内容使用 HLG 专用 EDR metadata

- **来源**: KI-010 修复（CAEDRMetadata 缺失）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift
- **Agent 自检**: `swift build` 编译通过；`swift test` 中 EDR metadata 选择逻辑测试通过
- **真机验证**: 播放 HLG 视频 → 色彩自然不过曝 → 日志显示使用 CAEDRMetadata.hlg
- **退化信号**: HLG 视频使用了 hdr10 metadata 而非 hlg、色彩过曝或偏暗
- **状态**: active
- **创建日期**: 2026-03-17


### REG-062: SDR 内容不设置 EDR metadata

- **来源**: KI-010 修复（防止 SDR 内容被误标为 HDR）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift
- **Agent 自检**: `swift build` 编译通过；`swift test` 中 SDR → edrMetadata = nil 测试通过
- **真机验证**: 播放 SDR 视频 → 显示效果与改动前一致 → 不出现异常亮度
- **退化信号**: SDR 视频出现不自然的高亮度、edrMetadata 不为 nil
- **状态**: active
- **创建日期**: 2026-03-17


### REG-063: HDR 开关同步更新 EDR metadata

- **来源**: KI-010 修复（HDR on/off 切换一致性）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift 中 setHDREnabled
- **Agent 自检**: `swift build` 编译通过；`swift test` 中 HDR 开关同步测试通过
- **真机验证**: HDR 视频播放中 → 关闭 HDR → 高光区域亮度降低 → 重新开启 HDR → 高光恢复
- **退化信号**: 切换后视觉效果无变化、切换后 edrMetadata 状态与开关不一致
- **状态**: active
- **创建日期**: 2026-03-17


---


## 全景渲染回归项


### REG-070: 360 全景视频在 ImmersiveSpace 中正确渲染

- **来源**: Panorama 渲染管线实现
- **触发条件**: 改动 SpatialScene/Renderers/*、PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift 中 detectProjectionType
- **Agent 自检**: `swift build` 编译通过；`swift test` 中投影类型检测测试通过
- **真机验证**: 打开带 GSpherical 元数据的 360 equirectangular 视频 → 自动进入 ImmersiveSpace → 球体内全方向视频正确铺满 → 转动头部方向一致
- **退化信号**: 视频未自动进入沉浸空间、球面映射扭曲或翻转、视频只在前方显示而非全方向
- **状态**: active
- **创建日期**: 2026-03-17


### REG-071: 180 全景视频前半球渲染正确

- **来源**: Panorama 渲染管线实现
- **触发条件**: 改动 SpatialScene/Renderers/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 打开 180 度全景视频 → 前半球有内容、后半球空白或黑色 → 内容位于视野正前方
- **退化信号**: 内容未居中到前方、180 度视频被拉伸到 360 度、后半球出现重复内容
- **状态**: active
- **创建日期**: 2026-03-17


---


## Phase 3 UI/UX 重构回归项


### REG-080: 统一时间轴拖动 seek 与精确时间显示

- **来源**: T3.3 进度条统一（替代 REG-010/011/014）
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/UseCases/DetailedTimelineGeometry.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频 → 拖动进度条 → 拖动期间显示精确时间标签（橙色，含帧号） → 松手后跳转到对应位置 → 时间标签与实际位置一致
- **退化信号**: 拖动时无精确时间标签、seek 位置不准、松手后 snap-back
- **状态**: active
- **创建日期**: 2026-04-02


### REG-081: 逐帧步进按钮在播放控件中可用

- **来源**: T3.3 进度条统一（替代 REG-017）
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlaybackCore/*
- **Agent 自检**: `swift build` 编译通过；`swift test --filter V04Tests` 通过
- **真机验证**: 播放视频 → secondaryControlRow 中可见前一帧/后一帧按钮 → 点击前一帧画面后退一帧 → 点击后一帧画面前进一帧
- **退化信号**: 按钮不可见、点击无响应、方向反了、一次点击跨越多帧
- **状态**: active
- **创建日期**: 2026-04-02


### REG-082: 视频详情页展示元数据并确认播放

- **来源**: T3.2b 视频详情界面（新功能）
- **触发条件**: 改动 PlayerUI/Views/VideoDetailView.swift、App/PlaybackLaunchCoordinator.swift、App/PreparedPlayback.swift、FileBrowsing/ViewModels/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 文件浏览器中选择视频 → 推入详情页 → 显示文件名、分辨率、HDR 类型、帧率、文件大小 → 音频轨道和字幕轨道列表正确 → 点击 Play → 正常播放
- **退化信号**: 详情页无法打开、元数据不显示、音轨列表为空（有多音轨文件时）、Play 按钮无响应、播放未通过 coordinator
- **状态**: active
- **创建日期**: 2026-04-02


### REG-083: 详情页返回正确取消预热

- **来源**: T3.2a 准备/确认拆分（新功能）
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、App/PreparedPlayback.swift、PlayerUI/Views/VideoDetailView.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 选择视频 → 进入详情页 → 不点 Play，点返回 → 回到文件列表 → 无残留播放状态、无视频画面闪现
- **退化信号**: 返回后残留播放状态、mpv 未停止预加载、内存泄漏（反复进出详情页后内存持续增长）
- **状态**: active
- **创建日期**: 2026-04-02


### REG-084: 沉浸空间全局入口可用

- **来源**: T3.4 沉浸空间全局入口（新功能）
- **触发条件**: 改动 App/Navigation/*、ToggleImmersiveSpaceButton.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 应用启动 → 工具栏右上角可见沉浸空间 toggle → 点击打开沉浸空间 → 再次点击关闭 → 切换标签页后 toggle 状态保持一致
- **退化信号**: toggle 不可见、打开后无法关闭、切换标签页后状态不同步、播放中仍显示 toggle（应隐藏）
- **状态**: active
- **创建日期**: 2026-04-02


### REG-085: Settings 播放结束行为和默认倍速持久化

- **来源**: T4.2 B2/B3 播放行为设置（新功能）
- **触发条件**: 改动 Settings/Views/*、Persistence/Adapters/UserDefaultsStore.swift、Persistence/Domain/Entities/UserPreferences.swift、App/PlaybackLaunchCoordinator.swift
- **Agent 自检**: `swift build` 编译通过 + `swift test` 测试通过
- **真机验证**: Settings → 修改"When Video Ends"为 Repeat → 修改"Default Speed"为 1.5x → 退出并重启 App → 设置保持 → 播放视频确认以 1.5x 速度开始
- **退化信号**: 设置不显示、选择不保存、重启丢失、默认速度不生效
- **状态**: active
- **创建日期**: 2026-04-02

### REG-086: 默认播放速度生效

- **来源**: T4.2 B3 默认倍速（新功能）
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、PlaybackCore/Domain/ValueObjects/PlaybackSpeed.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: Settings 设置默认倍速为 2.0x → 播放视频 → 确认起始速度为 2.0x → 通过详情页确认播放也以 2.0x 开始
- **退化信号**: 播放以 1.0x 开始而非设置的默认值
- **状态**: active
- **创建日期**: 2026-04-02

### REG-087: 播放结束自动下一集

- **来源**: T4.2 E2 自动下一集（新功能）
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、App/MainView.swift、XrPlayerApp.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: Settings 设为"Play Next" → 播放文件列表中的非末尾文件 → 播放结束后自动开始下一个文件 → 播放末尾文件时结束后停止（无下一个）→ 设为"Repeat"时循环当前文件 → 设为"Stop"时正常停止
- **退化信号**: 播放结束后无反应、跳到错误文件、Repeat 不循环、nextFileProvider 闭包泄漏
- **状态**: active
- **创建日期**: 2026-04-02

### REG-088: 视频详情页恢复播放提示

- **来源**: T4.2 C2 恢复播放 UX（新功能）
- **触发条件**: 改动 PlayerUI/Views/VideoDetailView.swift、App/PlaybackLaunchCoordinator.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频到中间 → 停止 → 重新选择同一视频 → 详情页显示"Resume from X:XX"和"Play from Start" → Resume 按钮从上次位置恢复 → Play from Start 从头开始 → 首次播放的视频只显示 Play 按钮
- **退化信号**: 恢复按钮不出现、恢复位置错误、首次播放出现恢复提示、alwaysResume 模式不自动恢复
- **状态**: active
- **创建日期**: 2026-04-02

### REG-089: 文件列表进度指示

- **来源**: T4.2 C3 进度指示 UX（新功能）
- **触发条件**: 改动 FileBrowsing/Views/*、FileBrowsing/ViewModels/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频到中间 → 返回文件列表 → 该文件显示橙色圆点和"Watched X:XX" → 未播放过的文件无进度指示 → 刷新文件列表后进度指示保持
- **退化信号**: 进度指示不显示、时间格式错误、已播放文件无标记、刷新后丢失
- **状态**: active
- **创建日期**: 2026-04-02


### REG-090: Photo Library 数据源

- **来源**: T4.2 E1 Photo Library 源（新功能）
- **触发条件**: 改动 FileBrowsing/Adapters/PhotoLibrary/*、FileBrowsing/ViewModels/*、FileBrowsing/Views/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 文件浏览器 → Folder → Photo Library... → 授权弹窗出现 → 授权后显示视频列表 → 视频文件名和大小正确 → 进入相册文件夹浏览 → 选择视频可正常播放 → 拒绝授权时显示错误提示
- **退化信号**: Photo Library 按钮不出现、授权弹窗不触发、视频列表为空、视频无法播放、相册不显示
- **状态**: active
- **创建日期**: 2026-04-02

### REG-091: 缓存清理策略

- **来源**: T4.2 E3 缓存清理（新功能）
- **触发条件**: 改动 App/XrPlayerApp.swift、Persistence/Adapters/SwiftDataStore.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 创建 >5 天前的播放进度记录 → 重启 App → 过期进度记录被清除 → 未过期记录保留
- **退化信号**: 过期记录未清除、所有记录被清除、启动崩溃
- **状态**: active
- **创建日期**: 2026-04-02

### REG-092: 网络中断重连

- **来源**: T4.2 E4 网络重连（新功能）
- **触发条件**: 改动 FileBrowsing/ViewModels/*、FileBrowsing/Views/*、FileBrowsing/Adapters/SMB/*、FileBrowsing/Adapters/WebDAV/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 连接 SMB/WebDAV 服务器 → 断开网络 → 浏览文件触发错误 → 恢复网络 → 点击 Retry 按钮 → 文件列表恢复 → 自动重连失败时显示错误弹窗
- **退化信号**: Retry 按钮不出现、自动重连无限循环、重连后路径丢失、错误信息不显示
- **状态**: active
- **创建日期**: 2026-04-02


### REG-093: 自动下一集无下一集时恢复控件

- **来源**: ce-review P1-1 — handlePlaybackEnded().playNext 空结果修复
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、MainView.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: Settings 设置 When Video Ends = Play Next → 播放最后一个文件 → 播放结束 → 控件自动显示（不卡死）
- **退化信号**: 控件不出现、界面冻结、需要手动点击才能恢复
- **状态**: active
- **创建日期**: 2026-04-02


### REG-094: Photo Library 临时文件过期清理

- **来源**: ce-review P1-2 — 导出视频临时文件无限累积修复
- **触发条件**: 改动 XrPlayerApp.swift、FileBrowsing/Adapters/PhotoLibrary/*
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 使用 Photo Library 播放视频 → 5 天后检查 tmp/xrplayer-photos/ → 过期文件已被清理
- **退化信号**: 临时文件持续增长、清理删除了活跃文件
- **状态**: active
- **创建日期**: 2026-04-02


### REG-095: PlaybackLaunching 协议签名一致性

- **来源**: QA Round 11 — confirmPlayback 签名与协议不匹配导致编译失败
- **触发条件**: 改动 App/PlaybackLaunching.swift、App/PlaybackLaunchCoordinator.swift
- **Agent 自检**: `xcodebuild build` 编译通过（visionOS Simulator target）
- **真机验证**: 编译通过即验证 — 协议一致性是编译期保证
- **退化信号**: PlaybackLaunchCoordinator 不再遵循 PlaybackLaunching 协议
- **状态**: active
- **创建日期**: 2026-04-02

### REG-096: PhotoLibraryDataSourceAdapter 相册内视频列表

- **来源**: QA Round 11 — PHAsset.fetchAssetsIn API 调用错误导致编译失败
- **触发条件**: 改动 FileBrowsing/Adapters/PhotoLibrary/PhotoLibraryDataSourceAdapter.swift
- **Agent 自检**: `xcodebuild build` 编译通过
- **真机验证**: Photo Library → 进入相册文件夹 → 视频列表正确显示
- **退化信号**: 相册内无视频、编译失败、fetchAssets 调用错误
- **状态**: active
- **创建日期**: 2026-04-02


---


## 沉浸影院 / 全景 / 播放路由回归项（v2 overnight）


### REG-100: 虚拟屏幕实体创建与渲染

- **来源**: T1.1 沉浸影院模式 — 虚拟屏幕实体
- **触发条件**: 改动 SpatialScene/Renderers/VirtualScreenEntity.swift、SpatialScene/Scenes/ImmersiveSpaceView.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter VirtualScreenConfigTests` 通过
- **真机验证**: 进入沉浸影院模式 → 虚拟屏幕出现在正前方 → 视频正常渲染到屏幕上 → 画面清晰无闪烁
- **退化信号**: 虚拟屏幕不出现、画面黑屏、纹理拉伸/翻转、进入沉浸空间后崩溃
- **状态**: active
- **创建日期**: 2026-04-02


### REG-101: 虚拟屏幕平面/曲面切换

- **来源**: T1.1 屏幕形状切换逻辑
- **触发条件**: 改动 SpatialScene/Renderers/VirtualScreenEntity.swift、SpatialScene/Domain/VirtualScreenConfiguration.swift、Settings/Views/SettingsView.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter VirtualScreenConfigTests` 通过
- **真机验证**: 沉浸影院模式播放中 → Settings 切换 Screen Shape 为 Curved → 屏幕变为曲面 → 切回 Flat → 恢复平面 → 播放不中断
- **退化信号**: 切换后屏幕消失、形状未变化、切换后法线翻转（从外侧看到画面）、切换导致崩溃
- **状态**: active
- **创建日期**: 2026-04-02


### REG-102: 屏幕位置调节可用

- **来源**: T1.2 屏幕位置控制
- **触发条件**: 改动 SpatialScene/Scenes/ImmersiveSpaceView.swift、Persistence/Domain/Entities/SavedScreenPosition.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter ScreenPositionValidationTests` 通过
- **真机验证**: 沉浸影院模式 → 调节距离 Slider（2m-20m）→ 屏幕前后移动 → 调节高度 Slider → 屏幕上下移动 → 调节旋转 Slider（±45°）→ 屏幕倾斜
- **退化信号**: Slider 拖动无反应、屏幕位置不变、超出边界值（<2m 或 >20m）
- **状态**: active
- **创建日期**: 2026-04-02


### REG-103: 环境独立位置记忆

- **来源**: T1.2 每个环境独立的位置记忆
- **触发条件**: 改动 AppModel.swift、Persistence/Domain/Entities/SavedScreenPosition.swift、Settings/Views/SettingsView.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter ScreenPositionValidationTests` 通过
- **真机验证**: 暗黑影院环境中调整距离为 5m → 切换到星空夜景 → 距离恢复为该环境记忆值 → 切回暗黑影院 → 距离恢复为 5m
- **退化信号**: 切换环境后位置未恢复、所有环境共享同一位置、位置记忆丢失
- **状态**: active
- **创建日期**: 2026-04-02


### REG-104: 沉浸影院环境切换

- **来源**: T1.3 三个沉浸式环境
- **触发条件**: 改动 SpatialScene/Renderers/EnvironmentDomeEntity.swift、SpatialScene/Views/SceneSelectorView.swift、SpatialScene/Scenes/ImmersiveSpaceView.swift、Settings/Views/SettingsView.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter CinemaEnvironmentTests` 通过
- **真机验证**: SceneSelectorView → 点击暗黑影院按钮 → 背景变为近黑色 → 点击星空夜景 → 背景变为深蓝色 → 点击自然日落 → 背景变为暖琥珀色 → 播放不中断
- **退化信号**: 环境按钮无响应、背景颜色不变、切换导致播放中断或崩溃、dome entity 未创建
- **状态**: active
- **创建日期**: 2026-04-02


### REG-105: 180° 半球裁剪渲染

- **来源**: T1.4 全景视频完善 — 半球裁剪
- **触发条件**: 改动 SpatialScene/Renderers/PanoramaSphereEntity.swift、SpatialScene/Domain/HemisphereMeshConfiguration.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter HemisphereMeshConfigTests` 通过
- **真机验证**: 打开 180° 全景视频 → 前半球正确显示内容 → 后半球无内容（黑色或透明）→ 内容居中于视野正前方 → 无拉伸或扭曲
- **退化信号**: 180° 视频被拉伸到 360°、后半球出现重复内容、UV 映射错误导致画面错位
- **状态**: active
- **创建日期**: 2026-04-02


### REG-106: Stereo 3D SBS/OU 帧分离渲染

- **来源**: T1.4 全景视频完善 — 立体 3D
- **触发条件**: 改动 SpatialScene/Renderers/PanoramaLayerBridge.swift、PlaybackCore/Domain/ValueObjects/StereoLayout.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter StereoFrameSplitTests` 通过
- **真机验证**: 打开 SBS 立体视频 → 画面只显示左半帧（非左右并排）→ 打开 OU 立体视频 → 画面只显示上半帧（非上下堆叠）→ 画面比例正确（无水平/垂直拉伸）
- **退化信号**: SBS 视频仍显示左右并排画面、OU 视频仍显示上下堆叠、裁剪区域错误、输出尺寸不正确
- **状态**: active
- **创建日期**: 2026-04-02


### REG-107: 鱼眼投影重映射

- **来源**: T1.4 全景视频完善 — 鱼眼重映射
- **触发条件**: 改动 Shared/VideoShaders.metal、SpatialScene/Renderers/PanoramaLayerBridge.swift、SpatialScene/Domain/FisheyeRemapConfiguration.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter FisheyeRemapConfigTests` 通过
- **真机验证**: 打开鱼眼投影视频 → Metal compute shader 将鱼眼映射为等距矩形 → 全景球体中画面无桶形畸变 → 中心和边缘区域均无明显失真
- **退化信号**: 鱼眼视频未被重映射（圆形画面仍可见）、重映射后画面严重失真、compute shader 崩溃
- **状态**: active
- **创建日期**: 2026-04-02


### REG-108: 投影类型手动覆盖

- **来源**: T1.4 投影类型手动覆盖 UI
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、AppModel.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 播放视频 → PlayerControlsView 中投影 Picker 显示当前检测结果 → 手动选择 panorama360 → 视频以全景球体渲染 → 手动选回 Auto → 恢复自动检测
- **退化信号**: Picker 不显示、选择后无效果、切换新视频时旧覆盖残留
- **状态**: active
- **创建日期**: 2026-04-02


### REG-109: 播放模式自动路由

- **来源**: T1.5 播放模式自动路由
- **触发条件**: 改动 PlayerUI/UseCases/DecidePlaybackModeUseCase.swift、PlayerUI/Views/PlayerControlsView.swift、App/PlaybackLaunchCoordinator.swift、SpatialScene/Scenes/ImmersiveSpaceView.swift
- **Agent 自检**: `swift build` 编译通过；`swift test --filter PlaybackModeRoutingTests` 通过
- **真机验证**: 播放 flat 视频 → 窗口模式 → 进入沉浸空间 → 自动切换为沉浸影院 → 播放 360° 视频 → 自动全景模式 → 手动覆盖为窗口模式 → 模式正确切换 → 切换另一视频 → 覆盖清除，重新自动路由
- **退化信号**: 视频类型与模式不匹配、手动覆盖不生效、新视频继承旧覆盖、模式切换导致崩溃或画面丢失
- **状态**: active
- **创建日期**: 2026-04-02


### REG-110: 沉浸影院模式视频 Bridge 接通

- **来源**: v3 overnight Phase 2 — F3.2 bridge 断联修复（Round 12）
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift 中 switchPlaybackMode() 逻辑
- **Agent 自检**: `swift build` 编译通过；grep PlayerControlsView.swift 确认 `.panorama || .immersive` 条件
- **真机验证**: 进入沉浸影院模式播放视频 → VirtualScreenEntity 显示视频纹理（非黑屏）→ 返回窗口模式 → 视频继续正常播放
- **退化信号**: 沉浸模式虚拟屏幕黑屏、bridge attachVideoLayer 未在 .immersive 触发、仅 .panorama 可见视频
- **状态**: active
- **创建日期**: 2026-04-02


### REG-111: 网络缓冲 ProgressView 指示器

- **来源**: v3 overnight Phase 2 — F4.1 缓冲指示器修复（Round 13）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift observeCoreProperties、App/MainView.swift
- **Agent 自检**: `swift build` 编译通过；grep MPVPlayerAdapter.swift 确认 "paused-for-cache" 被观察；grep MainView.swift 确认 .buffering 分支
- **真机验证**: 播放网络视频（SMB/WebDAV）且网络变慢时 → UI 中央出现 "Buffering…" 旋转指示器 → 网络恢复后指示器消失并自动继续播放
- **退化信号**: 缓冲时无 UI 反馈、PlaybackState.buffering 永远不触发、指示器出现后不消失
- **状态**: active
- **创建日期**: 2026-04-02


### REG-112: HDR/SDR 输出切换 UI

- **来源**: v3 overnight Phase 2 — F5.2 HDR/SDR 切换 UI（Round 13）
- **触发条件**: 改动 PlayerUI/Views/PlaybackMenuView.swift
- **Agent 自检**: `swift build` 编译通过；grep PlaybackMenuView.swift 确认 "Video Output" section 和 isHDRContent 条件
- **真机验证**: 播放 HDR10 视频 → 播放菜单中出现 "Video Output" section + HDR Toggle → 关闭 HDR → 视频以 SDR 输出 → 再次打开 HDR → 恢复
- **退化信号**: HDR 内容播放时菜单无 Video Output 选项、SDR 内容时误显示 Toggle、Toggle 改变无效果
- **状态**: active
- **创建日期**: 2026-04-02


### REG-113: 网络断线自动重连指数退避

- **来源**: v3 overnight Phase 2 — F4.3 自动重连（Round 13）
- **触发条件**: 改动 App/PlaybackLaunchCoordinator.swift、新建 App/NetworkMonitor.swift
- **Agent 自检**: `swift build` 编译通过；NetworkMonitor.swift 存在；PlaybackLaunchCoordinator 有 retryPlayback() 方法
- **真机验证**: 播放网络视频时断网 → App 自动重试 2s/4s/8s（最多 3 次）→ 断网时不对本地文件重试 → 重连后恢复播放
- **退化信号**: 断网后 App 立即放弃不重试、本地文件错误时也触发重试、重试超过 3 次、重试间隔不是指数增长
- **状态**: active
- **创建日期**: 2026-04-02


### REG-114: 本地子文件夹导航

- **来源**: v3 overnight Phase 2 — ISSUE-004 本地导航修复（Round 14）
- **触发条件**: 改动 FileBrowsing/ViewModels/FileBrowsingViewModel.swift navigateToFolder/navigateUp/loadFiles
- **Agent 自检**: `swift build` 编译通过；grep FileBrowsingViewModel.swift 确认 navigateToFolder 无 guard activeRemoteAdapter 阻断
- **真机验证**: 打开本地文件浏览 → 点击子文件夹 → 进入子目录（文件列表更新）→ 点击返回 → 回到上层目录 → 文件列表正确
- **退化信号**: 点击本地子文件夹无反应、navigateToFolder 被 guard 阻断、loadFiles 仍 hardcoded "." 忽略路径栈
- **状态**: active
- **创建日期**: 2026-04-02


### REG-115: 屏幕形状（平面/曲面）跨会话持久化

- **来源**: v3 overnight Phase 2 — F6.6 屏幕形状持久化（Round 14）
- **触发条件**: 改动 Persistence/Domain/Entities/UserPreferences.swift、Persistence/Adapters/UserDefaultsStore.swift、Settings/Views/SettingsView.swift、App/XrPlayerApp.swift
- **Agent 自检**: `swift build` 编译通过；UserPreferences 有 isScreenCurved 字段；UserDefaultsStore 有 screenShapeKey
- **真机验证**: 设置屏幕为曲面 → 退出 App → 重新进入沉浸空间 → 屏幕仍为曲面（非默认平面）
- **退化信号**: 重启后屏幕总是重置为平面、UserDefaults 未写入屏幕形状、SettingsView onChange 未触发持久化
- **状态**: active
- **创建日期**: 2026-04-02


### REG-116: 长按预览松开后恢复原速度

- **来源**: v3 overnight Phase 2 — H03 长按速度恢复（Round 15）
- **触发条件**: 改动 App/MainView.swift onLongPressBegan/onLongPressEnded 逻辑
- **Agent 自检**: `swift build` 编译通过；grep MainView.swift 确认 speedBeforeLongPress @State 变量
- **真机验证**: 设置播放速度为 0.5x → 长按捏合手势（预览变为 2x）→ 松开 → 速度恢复 0.5x（而非 1.0x）
- **退化信号**: 松开后速度总是重置为 1.0x、speedBeforeLongPress 未保存当前速度、速度显示与实际不符
- **状态**: active
- **创建日期**: 2026-04-02


### REG-117: 捏合拖拽 Seek

- **来源**: v3 overnight Phase 2 — F3.9/H04 捏合拖拽（Round 15）
- **触发条件**: 改动 PlayerUI/UseCases/DisambiguateGestureUseCase.swift、App/MainView.swift .drag 处理
- **Agent 自检**: `swift build` 编译通过；DisambiguateGestureUseCase 有 onDragUpdate/onDragEnded 回调；MainView .drag case 有 seek 逻辑
- **真机验证**: 捏合手势识别后水平拖动 → 播放进度随拖拽变化（左移后退，右移前进）→ 松开手势后保持 seek 位置
- **退化信号**: .drag case 执行 break（空操作）、拖拽无 seek 效果、onDragUpdate 未触发
- **状态**: active
- **创建日期**: 2026-04-02


### REG-118: 沉浸环境 Skybox 纹理加载

- **来源**: v3 overnight Phase 2 — F6.2/F6.3 skybox 纹理（Round 17）
- **触发条件**: 改动 SpatialScene/Renderers/EnvironmentDomeEntity.swift、SpatialScene/Scenes/ImmersiveSpaceView.swift
- **Agent 自检**: `swift build` 编译通过；EnvironmentDomeEntity 有 loadSkyboxTexture() 异步方法；Assets.xcassets 含 StarryNight/SunsetNature
- **真机验证**: 进入沉浸空间 → 切换到 "Starry Night" 环境 → dome 显示星空纹理（非纯色）→ 切换到 "Sunset Nature" → dome 显示日落纹理
- **退化信号**: dome 仍为纯色、TextureResource 加载失败后无 fallback、skyboxAssetName 返回 nil 时崩溃
- **状态**: active
- **创建日期**: 2026-04-02


### REG-119: 拖拽进度条时显示二级时间轴

- **来源**: v3 overnight Phase 2 — G04 DetailedTimelineView 接线（Round 18）
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift sliderSection、新建 PlayerUI/Views/DetailedTimelineView.swift
- **Agent 自检**: `swift build` 编译通过；DetailedTimelineView.swift 存在；PlayerControlsView 有 isDraggingSlider 条件
- **真机验证**: 播放视频 → 开始拖拽进度 Slider → 出现带刻度线和时间标签的详细时间轴 → 松开后时间轴消失
- **退化信号**: DetailedTimelineGeometry 存在但无 View 消费（孤立）、拖拽时无时间轴出现、Slider 区域崩溃
- **状态**: active
- **创建日期**: 2026-04-02


### REG-120: VoiceOver 播放控件 AccessibilityLabel

- **来源**: v3 overnight Phase 2 — M03 VoiceOver P1 播放控件（Round 18）
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift、PlayerUI/Views/PlaybackMenuView.swift、PlayerUI/Views/VideoDetailView.swift、PlayerUI/Views/ScreenPositionControlView.swift
- **Agent 自检**: `swift build` 编译通过；grep -r "accessibilityLabel" XrPlayer/PlayerUI 输出 ≥ 10 行
- **真机验证**: 开启 VoiceOver → 播放视频 → 点击播放按钮时 VoiceOver 朗读 "Play"/"Pause"/"Replay" → 跳过按钮朗读 "Skip forward 10 seconds"/"Skip backward 10 seconds"
- **退化信号**: VoiceOver 朗读无意义文字（如按钮索引）、动态标签不随播放状态更新、播放控件无标注
- **状态**: active
- **创建日期**: 2026-04-02


### REG-121: 沉浸/全景空间拖拽旋转 + 捏合缩放

- **来源**: v3 overnight Phase 2 — UX-01 DragRotationModifier + UX-06 MagnifyGesture（Rounds 19-21）
- **触发条件**: 改动 SpatialScene/Modifiers/DragRotationModifier.swift、SpatialScene/Renderers/PanoramaSphereEntity.swift、SpatialScene/Renderers/VirtualScreenEntity.swift、SpatialScene/Scenes/ImmersiveSpaceView.swift
- **Agent 自检**: `swift build` 编译通过；DragRotationModifier.swift 存在；PanoramaSphereEntity 有 InputTargetComponent
- **真机验证**: 进入沉浸空间 → 拖拽手势旋转全景球/虚拟屏幕 → 旋转带弹性动画和惯性 → Pitch 不超过 ±30° → 捏合手势缩放（0.5x~2.0x）
- **退化信号**: 拖拽无效果（缺 InputTargetComponent）、旋转无弹性动画、Pitch 无限制导致倒立视角、缩放 > 2x 或 < 0.5x
- **状态**: active
- **创建日期**: 2026-04-02


### REG-122: GSpherical HFOV 计算区分 180°/360° 全景

- **来源**: v3 overnight Phase 2 — ISSUE-009 FOV hardcoded nil 修复（Round 24）
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift GSpherical 读取逻辑
- **Agent 自检**: `swift build` 编译通过；grep MPVPlayerAdapter.swift 确认 "GSpherical:InitialHorizontalFOVDegrees" 被读取
- **真机验证**: 播放 180-vr-test.mp4 → 检测为 panorama180（半球渲染）→ 播放 360-test-nasa.webm → 检测为 panorama360（全球渲染）→ 两者渲染范围明显不同
- **退化信号**: 180° VR 被误判为 360°（全球渲染导致内容拉伸）、HFOV 始终为 nil、FOV 计算返回负值或超过 360°
- **状态**: active
- **创建日期**: 2026-04-02


### REG-123: Hover 效果形状匹配按钮形状

- **来源**: QA Round 2 — P1 Hover 形状不匹配修复
- **触发条件**: 改动 PlayerUI/Views/ 或 FileBrowsing/Views/ 中任何含 `.hoverEffect` 的文件
- **Agent 自检**: `grep -r "hoverEffect(.highlight)" XrPlayer/` 返回零匹配；`grep -rc "hoverEffect(.lift)" XrPlayer/` 返回 ≥ 21 处
- **真机验证**: 注视圆形按钮 → 圆形 lift 效果；注视矩形按钮 → 矩形 lift 效果；无形状不匹配
- **退化信号**: 圆形按钮显示方形 hover、矩形按钮显示圆形 hover、hover 效果完全不可见
- **状态**: active
- **创建日期**: 2026-04-06


### REG-124: 播放控件纯透明度渐显渐隐

- **来源**: QA Round 2 — P1 控件动画修复
- **触发条件**: 改动 MainView.swift 中 showControls 赋值站点、ornament 定义或 PlayerControlsView.swift 中 registerInteraction
- **Agent 自检**: `grep "showControls = " XrPlayer/MainView.swift` — 每处(除初始化)都包裹在 `withAnimation(.easeInOut(duration: 0.4))` 中；MainView 中 `.transition(.opacity)` 存在
- **真机验证**: 控件出现 → 纯 opacity 渐显，无位移/缩放；控件消失 → 纯 opacity 渐隐；8 秒自动隐藏同样平滑
- **退化信号**: 控件出现伴随位移动画、缩放动画或突变（无渐变）
- **状态**: active
- **创建日期**: 2026-04-06


### REG-125: 播放模式几何约束

- **来源**: QA Round 2 — P1 播放模式层级约束修复（修正为几何约束）
- **触发条件**: 改动 PlayerUI/UseCases/DecidePlaybackModeUseCase.swift 或 PlayerUI/Views/PlayerControlsView.swift 中模式菜单
- **Agent 自检**: `swift test --filter PlaybackModeRouting` 全部通过；grep 确认 `allowedModes(for:)` 存在于 DecidePlaybackModeUseCase 中
- **真机验证**: 播放 2D 视频 → 设置菜单仅显示窗口+沉浸模式（无全景）；播放全景视频 → 显示全部三种模式；沉浸影院对所有内容可用
- **退化信号**: 2D 视频可切换全景模式、全景视频缺少模式选项、沉浸影院对 2D 视频不可用
- **状态**: active
- **创建日期**: 2026-04-06


### REG-126: 视频画布跟随窗口缩放

- **来源**: QA Round 2 — P2 视频画布不跟随缩放修复
- **触发条件**: 改动 WindowVideoView.swift、MainView.swift 中 GeometryReader 包裹区域、MPVNativeMetalLayerView.swift
- **Agent 自检**: grep 确认 MainView 中 `GeometryReader` 包裹 `WindowVideoView`；WindowVideoView 中 `containerSize` 参数存在；MPVNativeMetalLayerView 中 MoltenVK `> 1` workaround 保留
- **真机验证**: 拖拽窗口边缘缩放 → 视频画布同步缩放，无黑边或比例失真
- **退化信号**: 窗口缩放后视频不变大小、出现黑边、画面比例错误、缩放时崩溃
- **状态**: active
- **创建日期**: 2026-04-06


### REG-127: NLE 时间轴面板玻璃背景与按钮容纳

- **来源**: QA Round 2 — P2 NLE 时间轴修复
- **触发条件**: 改动 PlayerUI/Views/NLETimelineView.swift 或 PlayerUI/Views/TimelineRulerView.swift
- **Agent 自检**: grep NLETimelineView 确认 `.enchronGlassPanel()` 或等效玻璃材质、`.clipped()` 存在；TimelineRulerView 中 `DragGesture` 存在
- **真机验证**: NLE 面板可见玻璃背景 → 按钮不溢出面板边界 → 拖动尺标滚动时间轴
- **退化信号**: 面板透明无背景、按钮溢出面板、拖拽尺标无响应
- **状态**: active
- **创建日期**: 2026-04-06


### REG-128: 播放中菜单全程可交互（P0 回归）

- **来源**: V2 综合验收 Unit 1 — SeekBarView 属性隔离修复
- **触发条件**: 改动 PlayerUI/Views/PlayerControlsView.swift（controlBarPill / leftMenu / rightMenu）或 SeekBarView
- **Agent 自检**: `swift build` 编译通过；grep 确认 `SeekBarView` 是独立私有 struct 且 `playbackPosition` 仅在 SeekBarView 中被读取；`grep -n "playbackPosition" XrPlayer/PlayerUI/Views/PlayerControlsView.swift` 输出不含 controlBarPill 或 leftMenu/rightMenu 函数体内的引用
- **真机验证**: 播放视频时点击左侧 Menu → 二级菜单稳定展开可点击；点击右侧 Settings → 三级菜单不闪烁；播放开始后 <2s 内点菜单 → 菜单正常出现；快速连续点击 Menu 5 次 → 无闪烁或 UI 卡死
- **退化信号**: 菜单点击后立即收起、菜单内容闪烁、子项不可点击、播放中菜单无响应
- **状态**: active
- **创建日期**: 2026-04-06


### REG-129: 三轴路由约束矩阵（flat 禁 panorama）

- **来源**: V2 综合验收 Unit 4 — DecidePlaybackModeUseCase 三轴路由
- **触发条件**: 改动 PlayerUI/UseCases/DecidePlaybackModeUseCase.swift 或 PlayerUI/Domain 中 PlaybackMode/ProjectionType 相关
- **Agent 自检**: `swift test --filter PlaybackModeRouting` 26 个测试全部通过；grep 确认 `allowedModes(for:)` 存在；`swift test --filter PlaybackModeRouting` 中 `testUnit4_allowedModes_flat_doesNotContainPanorama` 通过
- **真机验证**: 播放 flat 内容 → Settings 菜单中 Panorama 项 disabled；播放 equirectangular360 内容 → 三种模式均可点击；手动将 flat 内容尝试切换到 Panorama → 被拦截回退至 Window
- **退化信号**: flat 内容可切换到 Panorama、全景内容缺少模式选项、约束矩阵测试失败
- **状态**: active
- **创建日期**: 2026-04-06


### REG-130: HDR 检测 gamma-based 决策树

- **来源**: V2 综合验收 Unit 3 — ProjectionDetection + HDR gamma 决策树
- **触发条件**: 改动 PlaybackCore/Adapters/MPV/MPVPlayerAdapter.swift 中 `inferHDRType` 或 `currentHDRMetadata`
- **Agent 自检**: `swift build` 编译通过；grep 确认 `hdr-format` 字符串不出现在 MPVPlayerAdapter.swift 中（已删除旧路径）；grep 确认 `gamma == "pq"` 和 `gamma == "hlg"` 存在于 `inferHDRType` 函数中；V04 HDR 相关测试通过
- **真机验证**: 播放 HDR10 内容（PQ gamma）→ PlayerControlsView 左菜单显示 "HDR10" Toggle；播放 HLG 内容 → 显示 "HLG"；播放 SDR 内容 → 无 HDR Toggle 显示
- **退化信号**: SDR 内容显示 HDR Toggle、HDR 内容未检测为 HDR、gamma 变更后菜单标签不随之更新
- **状态**: active
- **创建日期**: 2026-04-06


### REG-131: 缩略图两级缓存（NSCache + 磁盘）

- **来源**: V2 综合验收 Unit 7 — ThumbnailService actor + ThumbnailCache 两级缓存
- **触发条件**: 改动 FileBrowsing/Services/ThumbnailService.swift 或 FileBrowsing/Services/ThumbnailCache.swift
- **Agent 自检**: `swift build` 编译通过；grep 确认 `ThumbnailCache.shared` 在 ThumbnailService 中被使用；grep 确认 `memoryImage(forKey:)` 和 `diskImage(forKey:)` 调用顺序符合 hot→warm→cold；grep 确认 `AsyncSemaphore` 存在（并发限流）
- **真机验证**: 首次进入视频列表 → 占位图先显示，缩略图异步加载；二次进入同一页面 → 缩略图立即显示无闪烁（命中内存缓存）；重启应用后进入同一页面 → 缩略图较快显示（命中磁盘缓存）；快速滚动 LazyVGrid → UI 不卡顿
- **退化信号**: 缩略图每次重新加载闪烁、LazyVGrid 快速滚动卡顿、文件损坏时崩溃而非显示占位图
- **状态**: active
- **创建日期**: 2026-04-06


### REG-132: 数据源切换立即显示骨架屏

- **来源**: V2 综合验收 Unit 8 — connectToDataSource 立即清空 + SkeletonCardView
- **触发条件**: 改动 FileBrowsing/ViewModels/FileBrowsingViewModel.swift `connectToDataSource` 函数 或 FileBrowsing/Views/ContentGridView.swift skeleton 分支
- **Agent 自检**: `swift build` 编译通过；grep FileBrowsingViewModel.swift 确认 `files = []` 和 `isLoading = true` 在 `connectToDataSource` 函数开头（连接前立即执行）；grep ContentGridView 确认 `if isLoading { skeletonGrid }` 分支存在；grep 确认 `SkeletonCardView` 在 skeletonGrid 中被使用
- **真机验证**: 在 FileBrowsing 侧边栏切换到 WebDAV 数据源 → 立即看到骨架屏（旧内容消失），不停留旧内容 → 连接成功后骨架屏替换为实际内容；连接失败 → 显示错误态；快速连续切换两次 → 显示最后一次切换结果
- **退化信号**: 切换数据源后仍短暂显示旧内容、骨架屏不出现、骨架屏动画不播放
- **状态**: active
- **创建日期**: 2026-04-06


### REG-133: AccessibilityIdentifier 全量覆盖（Unit 9）

- **来源**: V2 E2E 验收 Unit 9 — accessibilityIdentifier 补充
- **触发条件**: 改动 FileBrowsing/Views/VideoCardView.swift、FileBrowsing/Views/ContentGridView.swift、App/Navigation/NavigationOrnament.swift、PlayerUI/Views/VideoDetailView.swift、PlayerUI/Views/PlayerControlsView.swift
- **Agent 自检**: `swift build` 编译通过；`grep -rn "accessibilityIdentifier" XrPlayer/FileBrowsing/Views/VideoCardView.swift` 输出包含 `FileBrowsing-VideoCard-button-`；`grep -rn "accessibilityIdentifier" XrPlayer/App/Navigation/NavigationOrnament.swift` 输出包含 `Navigation-Ornament-tab-` 和 `Navigation-Ornament-button-sceneSelector`；`grep -rn "accessibilityIdentifier" XrPlayer/PlayerUI/Views/VideoDetailView.swift` 输出包含 `videoDetail.playButton`、`videoDetail.environment-`、`videoDetail.subtitlePicker`、`videoDetail.audioTrackPicker`
- **真机验证**: 开启 VoiceOver → 浏览 FileBrowsing 视频卡片，每张卡片可被独立聚焦；导航 Ornament Tab 按钮可独立聚焦；VideoDetailView 中字幕/音轨 Picker 可通过辅助功能访问；PlayButton 在覆盖层上可独立聚焦
- **退化信号**: VoiceOver 无法区分同类型的多个卡片、Picker 在无障碍树中缺失、Tab 按钮无法通过 UI 自动化测试定位
- **状态**: active
- **创建日期**: 2026-04-06


---


## 回归集维护规则


### 何时新增回归项

1. 修复了一个 bug → 必须新增对应回归项（G14 强制要求，不可跳过）
2. 完成了 Exec Plan 里程碑 → 该里程碑的验收标准转化为回归项
3. 用户报告了真机上的问题 → KI 条目产生对应回归项
4. 架构不变量曾被违反 → 为该不变量新增结构检查回归项


### 何时退役回归项

1. 对应功能已被完全替换或移除
2. 已被自动化测试完全覆盖（须提供证据：具体测试用例名称）
3. 连续 3 个月未被触发且对应代码路径无任何改动


### 退役流程

将状态改为 `retired` → 填写退役日期和退役原因 → 在当月增量总结文档中记录。不删除条目本身。


### 总量控制

活跃回归项控制在 30-50 条。超过 50 条时必须审查是否有可退役的项目。每季度进行一次全面审查。


### 回归项标准格式

新增回归项时，使用以下格式：

    ### REG-{三位数}: {一句话标题}

    - **来源**: KI-{编号} / G{编号} / RES-{编号} / 版本验收标准
    - **触发条件**: 改动了 {目录/文件路径} 时需检查
    - **Agent 自检**: {具体命令 + 预期结果}，无法自检则写"无"
    - **真机验证**: {操作步骤} → {预期结果}
    - **退化信号**: {什么现象说明发生了回归}
    - **状态**: active / retired / merged
    - **创建日期**: YYYY-MM-DD

新增回归项后，必须同时更新顶部的"代码路径映射索引"表。
