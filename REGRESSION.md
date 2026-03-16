# Enchron 回归集

更新时间：2026-03-17


## 使用方式

1. Agent 改动代码前：检查本文件中"代码路径映射索引"，预判改动会触发哪些回归项
2. Agent 改动代码后：用 `git diff --name-only` 获取改动文件列表，与索引匹配，执行所有匹配的"agent 自检"项，列出所有匹配的"真机验证"项生成人类验证清单
3. Agent 修复 bug 后：必须在本文件新增对应的回归项（G14 强制要求）


## 代码路径映射索引

| 改动路径 | 关联回归项 |
|---------|-----------|
| PlaybackCore/Adapters/MPV/* | REG-001, REG-002, REG-015, REG-017, REG-018, REG-060, REG-061, REG-062, REG-063 |
| PlaybackCore/Domain/* | REG-001, REG-002, REG-015, REG-017, REG-018 |
| PlaybackCore/UseCases/* | REG-001, REG-002, REG-015, REG-017, REG-018 |
| PlayerUI/Views/DetailedTimelineView.swift | REG-010, REG-011, REG-014, REG-017 |
| PlayerUI/UseCases/DetailedTimelineGeometry.swift | REG-010, REG-014, REG-017 |
| PlayerUI/Views/PlayerControlsView.swift | REG-012, REG-013, REG-015, REG-016, REG-018, REG-019 |
| PlayerUI/Views/PlayerControlSurface.swift | REG-012, REG-013, REG-015, REG-016, REG-019 |
| PlayerUI/Views/PlaylistView.swift | REG-019 |
| PlayerUI/Views/PlaybackMenuView.swift | REG-018 |
| PlayerUI/Domain/* | REG-010, REG-012, REG-015, REG-016 |
| FileBrowsing/Adapters/SMB/* | REG-020, REG-021, REG-023 |
| FileBrowsing/Adapters/WebDAV/* | REG-022 |
| FileBrowsing/ViewModels/* | REG-019, REG-020, REG-021, REG-022, REG-023 |
| FileBrowsing/Domain/* | REG-020, REG-022 |
| FileBrowsing/Views/* | REG-020 |
| Persistence/Adapters/SwiftDataStore.swift | REG-030 |
| Persistence/Adapters/UserDefaultsStore.swift | REG-031 |
| Persistence/Adapters/KeychainStore.swift | REG-021 |
| Persistence/Domain/* | REG-030, REG-031 |
| App/PlaybackLaunchCoordinator.swift | REG-001, REG-019, REG-040 |
| App/AppCoordinator.swift | REG-040, REG-041 |
| App/MainView.swift | REG-041 |
| App/Navigation/* | REG-041 |
| SpatialScene/* | REG-050, REG-070, REG-071 |
| SpatialScene/Renderers/* | REG-070, REG-071 |

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
- **状态**: active
- **创建日期**: 2026-03-14


### REG-011: 二级进度条进入退出流畅

- **来源**: G2 + G5 质量门禁
- **触发条件**: 改动 PlayerUI/Views/DetailedTimelineView.swift
- **Agent 自检**: `swift build` 编译通过
- **真机验证**: 点击进度条区域 → 平滑切换到二级进度条模式 → 点击空白区域退出 → 恢复正常播放 UI，无残留元素
- **退化信号**: 切换时明显卡顿、退出后 UI 元素残留、进入/退出动画不平滑
- **状态**: active
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
- **状态**: active
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
- **状态**: active
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
