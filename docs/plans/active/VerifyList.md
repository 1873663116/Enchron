# VerifyList
source: docs/brainstorms/2026-04-06-v2-comprehensive-requirements.md
date: 2026-04-06

## 功能需求

### §5.4 播放控件交互 Bug (P0)
- [x] 播放中打开 Menu → 二级菜单稳定可见，无闪烁 — 来源：§5.4
- [x] 二级菜单项（Subtitles/Audio/Speed）可点击，三级菜单正确展开 — 来源：§5.4
- [x] 三级菜单可滚动、可选择，选中项生效 — 来源：§5.4
- [x] Settings → Playback Mode 可切换，受约束矩阵限制的项灰色禁用 — 来源：§5.4
- [x] 快速连续开关菜单无状态错乱 — 来源：§5.4
- [x] 菜单打开状态下不被自动隐藏逻辑关闭 — 来源：§5.4

### §5.5 HDR 视频详情页卡死 (P0)
- [x] SDR 视频详情页正常加载，无延迟 — 来源：§5.5
- [x] HDR10 / Dolby Vision / HLG 视频详情页正常加载，HDR 类型正确显示 — 来源：§5.5
- [x] 之前导致卡死的 HDR 视频 → 最多 3 秒后 UI 可交互 — 来源：§5.5
- [x] 超时后点击播放 → 视频正常启动 — 来源：§5.5

### §5.6 详情页首次加载元数据错误 (P0)
- [x] 进入文件夹 → 后台预读完成后 → 打开详情页 → 首次显示即为正确元数据 — 来源：§5.6
- [x] 预读未完成时打开详情页 → 显示 loading 后更新为正确值 — 来源：§5.6
- [x] 预读不阻塞 UI，文件列表滚动流畅 — 来源：§5.6
- [x] 快速切换文件夹 → 旧预读 Task 被正确取消，无 crash — 来源：§5.6
- [x] 缓存失效策略：文件修改时间变化时重新检测 — 来源：§5.6

### §5.9 沉浸空间行为 (P0)
- [x] §5.9a 所有进入沉浸空间的路径统一经过 PlaybackLaunchCoordinator — 来源：§5.9a
- [x] §5.9a 详情页"沉浸播放"和控件菜单切换行为一致 — 来源：§5.9a
- [x] §5.9b 进入 Immersive/Panorama 后 APP 主窗口不可见 — 来源：§5.9b
- [x] §5.9b 退出沉浸空间后主窗口正常恢复 — 来源：§5.9b
- [x] §5.9c 沉浸空间为 .full 独占模式，其他应用不可见 — 来源：§5.9c
- [x] §5.9d 点击沉浸空间中的视频纹理 → toggle 播放控件显示/隐藏（含暂停态） — 来源：§5.9d + 对抗审查 P2-1
- [x] §5.9d 控件宿主是独立 .plain window，可自由拖动 — 来源：§5.9d
- [x] openImmersiveSpace 失败 → 回退到 Window 模式 — 来源：§5.9

### §5.10 播放控件严格对齐 player.html (P0)
- [x] 控制栏 pill 按钮数量和顺序：Menu → Rew → Play → Fwd → NLE → Settings — 来源：§5.10
- [x] 控制栏 pill 间距和尺寸与 player.html 匹配 — 来源：§5.10
- [x] Menu 面板向上展开，右边缘对齐 Menu 按钮 — 来源：§5.10 + §4.2
- [x] Menu 面板内容顺序：HDR toggle → Subtitles → Audio Track → Playback Speed — 来源：§4.2
- [x] Settings 面板向上展开，左边缘对齐 Settings 按钮 — 来源：§5.10 + §4.2
- [x] Settings 面板内容：Playback Mode → Environment — 来源：§4.2
- [x] HDR 内容 → Menu 显示 HDR format label + ON/OFF toggle — 来源：§4.2
- [x] SDR 内容 → Menu 无 HDR toggle 项 — 来源：§4.2
- [x] mono 内容 → 3D 整项灰色禁用 — 来源：§4.2
- [x] SBS/TB 内容 → 3D 默认选中对应项，可切换为 Off — 来源：§4.2
- [x] 进度条：左侧当前时间，右侧剩余时间，中间滑块 — 来源：§4.2
- [x] 顶栏：返回按钮 + 视频标题 + 技术标签 — 来源：§4.2

### §5.7 文件浏览性能与交互 (P1)
- [x] §5.7a 50+ 文件列表滚动流畅，无明显卡顿 — 来源：§5.7a
- [x] §5.7b 切换远端数据源（WebDAV/SMB）时 skeleton shimmer 动画持续播放 — 来源：§5.7b
- [x] §5.7b 加载完成后替换为实际内容 — 来源：§5.7b
- [x] §5.7c 下拉刷新保持当前列表稳定，增量更新 — 来源：§5.7c
- [x] §5.7c 刷新完成有明确成功/失败反馈 — 来源：§5.7c

### §5.11 NLE 关闭动效 (P1)
- [x] NLE 时间轴关闭时向底部滑入收起，与打开动效对称 — 来源：§5.11
- [x] 快速连续 toggle 动画不中断不跳帧 — 来源：§5.11

### §5.8 视频画布窗口缩放 (P2)
- [x] 拖动窗口边缘放大 → 视频画布同步放大 — 来源：§5.8
- [x] 拖动窗口边缘缩小 → 视频画布同步缩小 — 来源：§5.8
- [x] 快速连续 resize → 画布跟随，无撕裂或黑边 — 来源：§5.8

## UI/UX
- [x] 播放控件容器使用 visionOS 原生 Liquid Glass / 系统材质 — 来源：§4.2 + §5.10
- [x] Menu/Settings 面板使用 visionOS 原生容器，形式结构与 HTML 一致 — 来源：§4.2
- [x] NLE 面板玻璃背景效果 — 来源：§4.2

## 边界与错误处理
- [x] HDR 检测超时 → fallback 默认 profile，UI 显示"部分元数据不可用" — 来源：§5.5
- [x] 元数据预读单文件超时 → 跳过该文件，继续预读其他文件 — 来源：§5.6
- [x] 沉浸空间 open 失败 → 回退 Window 模式 — 来源：§5.9
- [x] 远端连接缓慢（>5s）→ 加载动画持续不中断 — 来源：§5.7b
- [x] 下拉刷新失败 → 当前列表不变 + 显示失败反馈 — 来源：§5.7c

## 文档同步
<!-- review 时根据实际代码变更补全 -->
- [x] ARCHITECTURE.md — 补充沉浸空间入口统一路径约束（§5.9a immersiveSpaceRequest + MainView 处理器）到 Architecture Invariants
- [x] REGRESSION.md — 新增 REG-134~REG-140 共 7 条回归项：菜单闪烁(§5.4)、HDR超时(§5.5)、元数据预读(§5.6)、沉浸入口统一(§5.9a)、主窗口隐藏/恢复(§5.9b)、NLE动效(§5.11)、画布缩放(§5.8)
- [x] CLAUDE.md — 不涉及

## Review 发现项（已修复）
<!-- ce-review P1 findings，round 3 execute 已修复 -->
- [x] P1-1: MainView.swift dismiss 路径补 dismissWindow(id: "playerControls")，修复沉浸退出时控件窗口残留
- [x] P2-1: MediaProfilePrefetchService 过滤 SMB URL，避免无效 AVFoundation 请求
- [x] P2-2: Dolby Vision 检测回退为字符串字面量（visionOS SDK 不含公开常量），加注释说明
- [x] P2-6: mergeFiles/mergeFolders 的 Dictionary(uniqueKeysWithValues:) 改用 uniquingKeysWith 防 crash
- [x] P2-7: detectProfile 中 AVURLAsset 在 Task 取消时调用 asset.cancelLoading()
