# 架构与 UX 决策记录

> 本文档记录需求评审后的最终决策，优先级高于 Requirements.md 中的原始描述。

---

## 架构决策

### A1. 解码引擎风险规避
- **主方案**: libmpv 静态 XCFramework，参考 IINA `libmpv-darwin-build` 脚本适配 visionOS (`arm64-apple-xros`)
- **备选1**: VLCKit / MobileVLCKit（GPL 兼容，格式覆盖相当）
- **备选2**: FFmpegKit（预编译 Apple XCFramework）
- **不使用** AVFoundation（格式支持太少）
- **v0.1 spike**: 第一个垂直切片必须先验证 libmpv 能否在 visionOS 编译；失败则切 VLCKit
- **接口层不变**: `PlaybackControlling` 协议隔离解码引擎，切换只改 Adapter

### A2. SpatialScene TOCTOU 竞态修复
- `SceneRendering.prepareVirtualScreen()` 改为返回 `Result<FrameOutput, SceneUnavailableError>`
- 调用内部原子性检查场景状态，消除分步 isSceneActive 查询

### A3. PlayerUI 协调职责提取
- 提取 `PlaybackSession` 协调器至 App 层 (App/AppCoordinator.swift)
- 拥有: DecidePlaybackModeUseCase、帧路由、模式切换、MediaProfile 事件订阅
- PlayerUI 退化为 Humble View，不再 import SpatialScene

### A4. MediaIdentity 文件识别
- 引入 `MediaIdentity` 值对象（路径 + 文件大小 + 服务器指纹）
- Persistence 使用 MediaIdentity 存储进度，不用原始 URL

### A5. GestureDisambiguator 层级
- 200ms 状态机逻辑移入 `PlayerUI/UseCases/DisambiguateGestureUseCase`
- View 层只做 SwiftUI 手势事件翻译

### A6. 依赖注入组装
- 所有具体类型组装在 App/AppCoordinator.swift（组合根）
- 模块间只传协议接口，不传具体实例

---

## UX 决策

### U1. 手势消歧时间窗口
- **200ms → 降至 100ms**（可后续调至更低）
- 不做捏合微反馈动画（与移动端逻辑一致，无需额外视觉确认）

### U2. 拖拽捏合 scrubbing
- 忽略手臂疲劳问题
- 灵敏度参考移动端水平拖动（小幅度手腕动作即可覆盖合理时间范围）

### U3. 面板最小化（白条模式）
- **v1.0 暂时移除**，不实现
- 后续版本再考虑

### U4. 新手引导
- **暂时推迟**，v1.0 后加入

### U5. 二级进度条缩放控制
- 进度条下方增加一个**小白条滑块**，左右滑动控制时间轴密度
- 不用双手展开捏合

### U6. 虚拟屏幕距离控制
- 使用预设档位：近（4m）/ 舒适（8m）/ 影院（14m）
- 附加精细调节滑块（Fine Tune 模式）

### U7. 远程文件夹分页
- 首次加载前 50 个文件，滚动触底加载更多
- 顶部增加搜索/过滤输入框

### U8. 字幕/音轨面板
- **播放时单击屏幕**唤出播放菜单（包含字幕、音轨选项）
- 若干秒后自动消失（参考主流播放器逻辑，约 4-5 秒）
- 用户点击非菜单空白区域也可关闭

### U9. 命名规范
- 3D 虚拟空间统一称 **Environment**（不再叫"场景"）
- 三种播放方式统一称 **Playback Mode**（Window / Immersive / Panorama）

### U10. 全景模式 UI 锚点
- 半透明水平控制带（Control Band），固定在视线下方约 15-20° 处，世界坐标锚定（非头部追踪）
- 单次捏合在当前注视点生成菜单，0.3 秒内漂移到标准位置

---

## Xcode 项目信息

- 项目路径: `/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/`
- 项目文件: `XrPlayer.xcodeproj`
- 源码目录: `XrPlayer/XrPlayer/`
- RealityKit 内容包: `Packages/RealityKitContent/`
- 已有文件: XrPlayerApp.swift, ContentView.swift, ImmersiveView.swift, AppModel.swift, AVPlayerView.swift, AVPlayerViewModel.swift
