# Enchron v3 — 用户可感知功能全清单

> 生成时间: 2026-04-02 (v3 Round 1)
> 数据源: Requirements.md 2.1-2.5 + product_philosophy.md + design_docs/ + 代码审计
> 分类标准:
> - 🟢 已实现 + 已通过单元测试/结构验证（v2 248 tests + QA 97.75）
> - 🟡 代码存在但未在 Simulator/真机上做用户体验验证
> - 🔴 未实现 / 缺测试素材 / 存在已知缺陷
> - ⚪ MVP v1.0 范围外，推迟

**注意**: v2 的 "QA 97.75" 是代码结构验证分数，不是用户体验验证分数。绝大多数功能属于 🟡（代码可能正确，但未从用户视角验证过）。

---

## 1. 媒体源与格式支持（Requirements 2.1）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F1.1 | 本地文件系统浏览与播放 | 🟢 | LocalDataSourceAdapter 完整实现，swift test 覆盖 |
| F1.2 | Apple Photos 视频访问 | 🟡 | PhotoLibraryDataSourceAdapter 完整实现，PHAsset 导出到临时文件，未在 Simulator 上验证 |
| F1.3 | SMB 远程文件浏览与播放 | 🟡 | SMBDataSourceAdapter 完整实现（依赖 AMSMB2 条件编译），未在真实 SMB 服务器上验证 |
| F1.4 | WebDAV 远程文件浏览与播放 | 🟡 | WebDAVDataSourceAdapter PROPFIND 实现完整，1 个 integration test 被 SKIP（需真实服务器凭证） |
| F1.5 | MP4 容器格式播放 | 🟢 | libmpv 原生支持，有测试素材 |
| F1.6 | MKV 容器格式播放 | 🟢 | libmpv 原生支持，有测试素材（SDR-test.mkv） |
| F1.7 | MOV 容器格式播放 | 🔴 | libmpv 支持，**缺测试素材** |
| F1.8 | AVI 容器格式播放 | 🔴 | libmpv 支持，**缺测试素材** |
| F1.9 | SDR 视频播放 | 🟢 | swift test 覆盖 HDR 检测逻辑，SDR 为默认路径 |
| F1.10 | HDR10 检测与播放 | 🟡 | MPVPlayerAdapter.inferHDRType 实现完整，EDRMetadataDescriptor 映射正确，未用 HDR10 素材在设备上验证色彩 |
| F1.11 | HDR10+ 检测与播放 | 🔴 | 代码路径存在，**缺 HDR10+ 测试素材** |
| F1.12 | Dolby Vision 检测与播放 | 🟡 | dovi-profile 检测实现，映射为 HDR10 兼容模式（Apple 无公开 DoVI EDR API），未在设备上验证 |
| F1.13 | HLG 检测与播放 | 🔴 | arib-std-b67 gamma 检测实现，**缺 HLG 测试素材** |
| F1.14 | 4K/8K 超高码率视频播放 | 🟡 | libmpv + VideoToolbox 硬件解码，未做高码率压力测试 |
| F1.15 | SBS 左右格式 3D 立体视频 | 🔴 | ProjectionDetection + stereoCropMode 实现，**缺 SBS 测试素材**，且当前为左眼单目裁剪非真正立体 |
| F1.16 | OU 上下格式 3D 立体视频 | 🔴 | 同上，**缺 OU 测试素材** |
| F1.17 | 360° 全景视频 | 🟡 | PanoramaSphereEntity 全球体实现，UV 映射完整，未用真实 360° 素材在 Simulator 上验证 |
| F1.18 | 180° VR 视频 | 🟡 | 半球体 mesh 实现（UV [0.25,0.75]），v2 R14 修复了 UV 映射错误 |
| F1.19 | 鱼眼投影视频 | 🟡 | Metal compute shader fisheye_remap 存在（VideoShaders.metal:59），**缺鱼眼测试素材** |
| F1.20 | HDR 类型自动检测（无需用户操作） | 🟢 | inferHDRType + MediaProfile 检测链完整，swift test 覆盖 |
| F1.21 | 投影类型自动检测 | 🟡 | ProjectionDetection 实现完整，但 FOV 180/360 消歧硬编码 nil（TODO），默认 360° |
| F1.22 | 投影类型手动覆盖 | 🟢 | 投影覆盖 UI + effectiveProjectionType + 路由触发链已修复（v2 R14） |
| F1.23 | 图片格式浏览（JPEG/PNG/GIF/WebP/HEIF） | 🟡 | FileFilter 可能包含但未验证图片浏览功能是否存在于 UI |

---

## 2. 导航与播放选择（Requirements 2.2）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F2.1 | 启动即显示 UI 面板（Shared Space） | 🟡 | XrPlayerApp Scene 定义存在，IS-01 合规，未在 Simulator 上观察 |
| F2.2 | 场景选择面板 | 🟢 | SceneSelectorView 功能化（v2 R8），3 个真实环境按钮 |
| F2.3 | 面板最小化（白条 + 注视展开） | ⚪ | MVP 推迟，需 visionOS API 可行性研究 |
| F2.4 | 默认场景启动（偏好设置） | ⚪ | MVP 推迟 |
| F2.5 | 添加网络存储入口（SMB/WebDAV） | 🟡 | FileBrowserView "Add SMB" / "Add WebDAV" 菜单项存在，DataSourceConfigView 完整 |
| F2.6 | 文件浏览（多排序选项） | 🟢 | 按名称/日期/大小排序 + 升降序，LocalDataSourceAdapter 覆盖 |
| F2.7 | 播放进度指示（文件列表中） | 🟡 | 进度存储逻辑实现（SwiftDataStore），UI 端进度条显示未确认 |
| F2.8 | 文件选择后自动选择播放模式 | 🟢 | DecidePlaybackModeUseCase 决策矩阵 + autoRoutePlaybackMode 完整（v2 R9+R14 修复） |
| F2.9 | NavigationStack 左侧导航栏 | 🟡 | FileBrowserView 使用 NavigationStack，WN-04 合规性未验证 |

---

## 3. 播放模式与空间交互（Requirements 2.3）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F3.1 | 窗口模式播放 | 🟢 | v0.1 起稳定，MTKView 嵌入 SwiftUI，swift test 覆盖 |
| F3.2 | 沉浸场景模式 | 🟡 | VirtualScreenEntity + EnvironmentDomeEntity 实现，**环境为纯色（非纹理/Skybox）** |
| F3.3 | 全景模式（360°/180°/鱼眼） | 🟡 | PanoramaSphereEntity 投影完整，未在 Simulator 上验证视觉效果 |
| F3.4 | 播放模式自动切换 | 🟢 | DecidePlaybackModeUseCase + onChange(of: playbackMode) 响应空间 open/dismiss（v2 R14 修复） |
| F3.5 | 200ms 捏合手势消歧 | 🟡 | DisambiguateGestureUseCase 完整实现（longPressThreshold=0.2），**未确认是否接线到 visionOS 手势识别器** |
| F3.6 | 单次捏合 → 召唤主菜单 | 🟡 | 手势消歧逻辑存在，PlayerControlSurface 接线状态未确认 |
| F3.7 | 双次捏合 → 播放/暂停切换 | 🟡 | 同上 |
| F3.8 | 捏合长按 → 2.0x 倍速 | 🟡 | 同上 |
| F3.9 | 捏合拖拽 → 进度条直接拖拽 | 🟡 | dragDistanceThreshold=8pt 实现，UI 接线未确认 |
| F3.10 | 二级时间轴/精细 Scrubber | 🟡 | DetailedTimeline 存在，固定中心指针模型，未在 Simulator 上验证交互 |
| F3.11 | 当前文件夹视频列表/切换 | 🟡 | PlaylistMenuView 由 FileBrowsingViewModel.files 驱动，UI 未验证 |
| F3.12 | 播放/暂停 | 🟢 | PlayerControlsView 状态感知图标，swift test 覆盖 |
| F3.13 | ±10 秒快进快退 | 🟢 | skip buttons 实现完整 |
| F3.14 | 可变播放速度（0.25x-5.0x） | 🟢 | PlaybackSpeed.allCases 全量，速度菜单 UI 完整 |
| F3.15 | 音轨选择 | 🟡 | PlaybackMenuView 音轨面板存在，未在多音轨视频上验证 |
| F3.16 | 字幕选择 | 🟡 | 字幕面板存在，Noto Sans SC 字体打包，sub-fonts-dir 配置，未验证 CJK 渲染 |
| F3.17 | X 轴视角旋转（躺姿适配） | 🟡 | 屏幕位置面板含 viewAngle 控件，ScreenPositionStoring 实现 |
| F3.18 | 虚拟屏幕远近距离控制 | 🟡 | distance slider + clamping + 持久化（v2 R7），未在 Simulator 上体验 |
| F3.19 | 虚拟屏幕高度控制 | 🟡 | verticalOffset slider + clamping + 持久化（v2 R7） |
| F3.20 | 每个环境独立记忆屏幕位置 | 🟢 | ScreenPositionStoring per-environment 实现 + v2 R14 修复 nil 时重置默认值 |
| F3.21 | 逐帧步进按钮 | 🟡 | PlayerControlsView 含 frame-step forward/backward 按钮，未验证帧精度 |

---

## 4. 状态管理与错误处理（Requirements 2.4）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F4.1 | 网络缓冲动画（转圈） | 🔴 | **无缓冲指示器实现**，网络卡顿时用户看不到状态 |
| F4.2 | 网络断开错误提示 | 🟡 | PlaybackEvent.failed(.runtime) → UI 显示错误，但无"重试"按钮 |
| F4.3 | 后台静默重连 | 🔴 | **无自动重连逻辑**，mpv 报错后播放直接停止 |
| F4.4 | 播放进度记忆 | 🟢 | SwiftDataStore 实现，PlaybackLaunchCoordinator persist-on-teardown |
| F4.5 | 恢复播放弹窗（"从上次位置继续？"） | 🟡 | VideoDetailView resume button 实现，3 种 ResumePolicy，未在 Simulator 上测试交互 |
| F4.6 | "记住我的选择"开关 | 🟡 | SettingsView 有 resume behavior 选项，关联到 UserDefaultsStore |
| F4.7 | 文件列表进度提示 | 🔴 | 进度存储存在但**文件列表 UI 未确认显示进度条** |
| F4.8 | 5 天缓存自动清理 | 🟡 | PhotoLibraryDataSourceAdapter 有 5 天临时文件清理，播放进度缓存清理逻辑未确认 |
| F4.9 | 播放结束行为（停留最后帧 + 重播图标） | 🟡 | playbackEndBehavior 支持 stop/repeat/playNext，ended 状态图标切换存在 |
| F4.10 | 自动下一集 | 🟡 | nextFileProvider 接线完整（XrPlayerApp.init），按文件名排序取下一个 |

---

## 5. HDR 与色彩管理（Requirements 2.5）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F5.1 | HDR 标签显示（HDR10/DOLBY VISION/HLG） | 🟡 | Debug panel 有 HDR pipeline 状态，正式 HDR 标签 UI 位置未确认 |
| F5.2 | HDR/SDR 实时切换按钮 | 🔴 | **未找到实时切换 toggle 实现**（Requirements 要求控制栏有按钮） |
| F5.3 | Dolby Vision 硬件解码 | 🟡 | hwdec=videotoolbox 配置，DoVI profile 检测存在，映射为 HDR10 兼容 |
| F5.4 | 字幕 GPU 合成（blend-subtitles=yes） | 🟡 | mpv 配置存在但未验证 ASS 特效完整性 |

---

## 6. 沉浸场景与虚拟环境（Design Docs + Requirements 2.3）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F6.1 | 暗黑影院环境 | 🟡 | EnvironmentDomeEntity 实现，**纯色 UnlitMaterial（白0.02）非 Skybox 纹理** |
| F6.2 | 星空夜景环境 | 🟡 | 同上，深蓝色纯色 |
| F6.3 | 日落自然环境 | 🟡 | 同上，暗棕色纯色 |
| F6.4 | 环境切换（不退出沉浸空间） | 🟡 | switchEnvironment(to:) 实现，是否需要退出/重进 ImmersiveSpace 未验证 |
| F6.5 | 虚拟屏幕平面/曲面切换 | 🟡 | SettingsView 含 screenShape 切换，VirtualScreenEntity 支持 flat/curved |
| F6.6 | 屏幕形状持久化 | 🔴 | **AppModel.screenShape 不持久化**，重启后恢复默认 flat |
| F6.7 | 进入/退出沉浸空间过渡动画（IS-05 渐变调暗） | 🟡 | .immersionStyle 配置存在，实际过渡效果未在 Simulator 上验证 |

---

## 7. 设置与用户偏好（Design Docs + Requirements 2.4）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F7.1 | 恢复播放策略选择 | 🟡 | SettingsView 下拉菜单 → UserDefaultsStore 持久化 |
| F7.2 | 播放结束行为选择 | 🟡 | SettingsView 下拉菜单 → UserDefaultsStore 持久化 |
| F7.3 | 默认播放速度设置 | 🟡 | SettingsView slider → UserDefaultsStore 持久化 |
| F7.4 | 已连接服务器管理/删除 | 🟡 | FileBrowserView 含 saved data source chips + delete，DataSourceConfigView 完整 |
| F7.5 | 远程视频缓存清理 | 🔴 | **未找到显式的远程流缓存清理 UI** |
| F7.6 | 应用版本/关于页面 | 🔴 | **未找到 About 页面** |

---

## 8. 辅助功能与平台合规（HIG + Design Docs）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F8.1 | ≥60pt 交互目标（EH-02） | 🟡 | 未系统性验证所有按钮尺寸 |
| F8.2 | 注视+捏合为主交互（EH-01） | 🟡 | 手势消歧实现但 visionOS 手势识别器接线未确认 |
| F8.3 | 内容固定在世界空间（SL-07） | 🟡 | 未在 Simulator 上验证面板是否跟随头部 |
| F8.4 | VoiceOver 可访问性标签 | 🔴 | **未审计 accessibilityLabel 覆盖情况** |
| F8.5 | Ornament 位置合规（WN-04/WN-05） | 🟡 | 代码使用 Ornament 但具体锚定位置未验证 |

---

## 9. 性能与稳定性（Design Docs Capacity Estimation）

| # | 功能 | 状态 | 说明 |
|---|------|------|------|
| F9.1 | 60 分钟连续播放无崩溃 | 🔴 | **未执行长时间稳定性测试** |
| F9.2 | 内存增长 < 50MB（60分钟） | 🔴 | **未执行内存监控测试** |
| F9.3 | 帧丢率 < 1% | 🔴 | **未执行帧率监控测试** |
| F9.4 | 温度上升 < 8°C（60分钟） | ⚪ | 需真机测试，Simulator 无法测量 |
| F9.5 | 电池消耗 < 15%（60分钟） | ⚪ | 需真机测试 |

---

## 统计汇总

| 状态 | 数量 | 占比 |
|------|------|------|
| 🟢 已实现已验证 | 16 | 19% |
| 🟡 已实现未设备验证 | 46 | 56% |
| 🔴 未实现/缺素材/有缺陷 | 16 | 19% |
| ⚪ MVP 外推迟 | 4 | 5% |
| **总计** | **82** | 100% |

---

## TODOS.md 指出的被忽略领域 — 逐项对照

| 被忽略领域 | 对应功能 | 当前状态 |
|------------|----------|---------|
| 空间手势 200ms 消歧机制 | F3.5-F3.9 | 🟡 逻辑实现，visionOS 手势接线未确认 |
| 播放模式自动切换 UX | F3.4 | 🟢 代码修复完成，需 Simulator 验证 UX |
| 网络异常用户可见行为 | F4.1-F4.3 | 🔴 缺缓冲指示器 + 无自动重连 |
| 播放记忆恢复弹窗交互 | F4.5-F4.6 | 🟡 代码存在，需 Simulator 验证 |
| 播放结束行为 | F4.9-F4.10 | 🟡 三种策略实现完整，需验证 |
| 缓存清理策略 | F4.8, F7.5 | 🔴 Photo 临时文件有清理，远程流缓存清理缺失 |
| 视频格式测试素材 | F1.7-F1.8, F1.11, F1.13, F1.15-F1.16 | 🔴 缺 MOV/AVI/HDR10+/HLG/SBS/OU 素材 |

---

## 🔴 项优先级排序（Phase 2 修复候选）

### P0 — 影响核心功能
1. **F4.1 网络缓冲指示器** — 网络卡顿时用户完全无反馈
2. **F4.3 自动重连逻辑** — 网络恢复后需手动重新播放
3. **F5.2 HDR/SDR 实时切换按钮** — Requirements 明确要求，当前缺失
4. **F4.7 文件列表进度提示** — Requirements 明确要求 UI 显示

### P1 — 影响体验完整性
5. **F6.6 屏幕形状持久化** — 重启后丢失用户偏好
6. **F7.5 远程缓存清理 UI** — Settings 功能缺失
7. **F7.6 About 页面** — 基础 Settings 功能缺失
8. **F8.4 VoiceOver 可访问性** — visionOS 合规要求

### P2 — 测试素材（阻塞验证）
9. **F1.7 MOV 测试素材** — ffmpeg 转制即可
10. **F1.8 AVI 测试素材** — ffmpeg 转制即可
11. **F1.11 HDR10+ 测试素材** — 公开源获取
12. **F1.13 HLG 测试素材** — 公开源获取
13. **F1.15 SBS 测试素材** — ffmpeg 合成
14. **F1.16 OU 测试素材** — ffmpeg 合成
15. **F1.19 鱼眼测试素材** — 公开源获取

### 已知代码级缺陷
- **F1.21** FOV 180/360 消歧 — hardcoded nil（TODO in code），所有 GSpherical 视频默认 360°
- **F6.1-F6.3** 沉浸环境 — CinemaEnvironment.skyboxAssetName 定义了纹理名但从未加载，所有环境为纯色
