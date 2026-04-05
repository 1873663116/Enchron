# Phase 3 产出：模块间接口契约

> 本文档定义 Enchron 五个限界上下文之间的 Swift protocol 接口。这些接口是模块解耦的关键——各模块只依赖接口定义，不知道对方的内部实现。

---

## 1. PlaybackControlling — PlayerUI → PlaybackCore

PlayerUI 通过此接口控制播放核心。

```swift
/// 播放控制接口
protocol PlaybackControlling: AnyObject {
    /// 加载并播放指定 URL 的媒体文件
    func play(url: URL) async throws
    /// 暂停播放
    func pause()
    /// 恢复播放
    func resume()
    /// 停止播放并结束当前会话
    func stop()
    /// 取消当前加载/缓冲任务（例如用户快速切换视频）
    func cancelPendingLoad()
    /// 跳转到指定位置（秒）
    func seek(to seconds: Double)
    /// 快进/快退指定秒数
    func skip(by seconds: Double)
    /// 设置倍速
    func setSpeed(_ speed: PlaybackSpeed)
    /// 切换音轨
    func selectAudioTrack(_ track: AudioTrack)
    /// 切换字幕轨
    func selectSubtitleTrack(_ track: SubtitleTrack?)
    /// 获取当前播放状态（只读）
    var currentState: PlaybackState { get }
    /// 获取当前播放位置
    var currentPosition: PlaybackPosition { get }
    /// 获取可用音轨列表
    var availableAudioTracks: [AudioTrack] { get }
    /// 获取可用字幕轨列表
    var availableSubtitleTracks: [SubtitleTrack] { get }
}
```

---

## 2. FrameOutput — PlaybackCore → PlayerUI / SpatialScene

PlaybackCore 通过此接口输出解码帧。由 PlayerUI 或 SpatialScene 的渲染组件实现。

```swift
import CoreVideo

/// 帧输出接口
protocol FrameOutput: AnyObject {
    /// 接收解码后的视频帧
    /// - Parameter pixelBuffer: 来自 VideoToolbox 的解码帧，含 HDR 元数据
    func didOutputFrame(_ pixelBuffer: CVPixelBuffer)
}
```

---

## 3. MediaProfileDetecting — PlaybackCore → PlayerUI

PlaybackCore 识别出视频的画面特征后通知 PlayerUI。

```swift
/// MediaProfile 识别回调接口
protocol MediaProfileDetecting: AnyObject {
    /// 视频的 MediaProfile 已识别完成
    /// - Parameter profile: 包含投影类型、HDR 类型和分辨率
    func didDetectMediaProfile(_ profile: MediaProfile)
}
```

---

## 4. PlaybackEventListening — PlaybackCore → PlayerUI

播放状态变更事件的订阅接口。

```swift
/// 播放事件监听接口
protocol PlaybackEventListening: AnyObject {
    func playbackDidStart()
    func playbackDidPause()
    func playbackDidResume()
    func playbackDidEnd()
    func playbackDidUpdatePosition(_ position: PlaybackPosition)
    func playbackDidChangeSpeed(_ speed: PlaybackSpeed)
    func playbackDidSwitchTrack()
    func playbackDidEncounterError(_ error: PlaybackError)
}
```

---

## 4.1 PlaybackRuntimeManaging — PlaybackCore 内部运行时

为避免高频事件积压导致状态错乱，PlaybackCore 需要显式定义运行时控制接口。

```swift
/// 播放运行时控制接口
protocol PlaybackRuntimeManaging: AnyObject {
    /// 启动 libmpv 事件循环（后台线程）
    func startEventLoop()
    /// 停止事件循环并释放资源
    func stopEventLoop()
    /// 当前事件队列水位（用于诊断与监控）
    var eventQueueDepth: Int { get }
}
```

---

## 5. SceneStateProviding — SpatialScene → PlayerUI

PlayerUI 查询当前场景状态，用于播放模式决策。

```swift
/// 场景状态查询接口
protocol SceneStateProviding {
    /// 当前是否有虚拟场景处于活跃状态
    var isSceneActive: Bool { get }
    /// 当前活跃的虚拟场景标识（如果有）
    var activeEnvironmentID: String? { get }
}
```

---

## 6. SceneRendering — PlayerUI → SpatialScene

PlayerUI 决策后指示 SpatialScene 进行渲染。

```swift
/// 场景渲染控制接口
protocol SceneRendering: AnyObject {
    /// 准备虚拟屏幕以接收视频帧（沉浸场景模式）
    func prepareVirtualScreen() async throws
    /// 准备全景球体/半球体以接收视频帧（全景模式）
    /// - Parameter projectionType: 投影类型（360°/180°/鱼眼）
    func preparePanoramaSphere(for projectionType: ProjectionType) async throws
    /// 停止渲染并清理资源
    func stopRendering()
    /// 设置帧输出目标（SpatialScene 内部的渲染器作为 FrameOutput 实现）
    var frameReceiver: FrameOutput { get }
}
```

---

## 7. PlaybackModeManaging — PlayerUI 内部

播放模式切换接口。PlayerUI 的 `PlaybackModeSwitcher` 和 `DecidePlaybackModeUseCase` 通过此接口协调播放模式的自动决策和用户手动切换。

```swift
/// 播放模式管理接口
protocol PlaybackModeManaging: AnyObject {
    /// 当前播放模式
    var currentMode: PlaybackMode { get }
    /// 根据 MediaProfile + 场景状态自动决策播放模式
    func autoDecideMode(for profile: MediaProfile, sceneActive: Bool) -> PlaybackMode
    /// 用户手动切换播放模式（覆盖自动决策）
    func switchMode(to mode: PlaybackMode) async throws
    /// 当前模式是否支持手动切换到目标模式
    /// 例如：全景视频无法切换到窗口模式
    func canSwitch(to mode: PlaybackMode) -> Bool
}
```

---

## 8. SceneManaging — PlayerUI → SpatialScene

管理虚拟场景的进入/切换/退出。支持两种场景：
- **非播放时**：从场景选择页进入/切换（`SceneSelectorView`）
- **播放中**：通过播放界面的浮层快速切换（`SceneSwitcherView`）

```swift
/// 场景管理接口
protocol SceneManaging: AnyObject {
    /// 进入指定虚拟场景
    func enterEnvironment(_ environmentID: String) async throws
    /// 切换到另一个虚拟场景
    func switchEnvironment(to environmentID: String) async throws
    /// 退出当前虚拟场景，回到 Shared Space
    func exitEnvironment() async throws
    /// 获取可用场景列表
    var availableEnvironments: [VirtualEnvironmentInfo] { get }
    /// 调节虚拟屏幕位置
    func adjustScreenPosition(_ position: ScreenPosition)
    /// 调节视角旋转
    func adjustViewAngle(_ angle: ViewAngle)
}
```

---

## 9. FileProviding — FileBrowsing → App 层（由 App 获取 URL 后传给 PlaybackCore）

文件浏览模块对外暴露的统一文件获取接口。

```swift
/// 文件提供接口
protocol FileProviding {
    /// 获取指定文件夹下的媒体文件列表
    func listFiles(in folder: MediaFolder,
                   sortBy: SortCriteria) async throws -> [MediaFileInfo]
    /// 获取指定文件的可播放 URL
    func resolvePlayableURL(for file: MediaFileInfo) async throws -> URL
}
```

---

## 10. DataSourceConnecting — FileBrowsing 内部（防腐层接口）

统一的数据源连接接口，SMB/WebDAV/本地各自实现。

```swift
/// 数据源连接接口（防腐层）
protocol DataSourceConnecting {
    /// 连接到数据源
    func connect(with info: ConnectionInfo) async throws
    /// 断开连接
    func disconnect()
    /// 获取指定路径下的文件夹和文件列表
    func listContents(at path: String) async throws -> [FileSystemItem]
    /// 获取指定文件的可读取 URL/Stream
    func resolveURL(for item: FileSystemItem) async throws -> URL
    /// 当前连接状态
    var connectionStatus: ConnectionStatus { get }
}
```

---

## 11. 持久化接口族 — Persistence 对外暴露

### ProgressStoring

```swift
/// 播放进度存取接口
protocol ProgressStoring {
    /// 保存播放进度
    func saveProgress(_ progress: PlaybackProgress) async
    /// 查询指定文件的播放进度
    func loadProgress(for fileID: FileIdentifier) async -> PlaybackProgress?
    /// 清理过期进度（超过指定天数）
    func cleanExpiredProgress(olderThan days: Int) async
}
```

### PreferencesStoring

```swift
/// 用户设置存取接口
protocol PreferencesStoring {
    func loadPreferences() -> UserPreferences
    func savePreferences(_ preferences: UserPreferences)
}
```

### CredentialStoring

```swift
/// 凭证安全存取接口
protocol CredentialStoring {
    /// 保存连接凭证到 Keychain
    func saveCredential(for sourceID: String, credential: StorageCredential) throws
    /// 从 Keychain 读取凭证
    func loadCredential(for sourceID: String) throws -> StorageCredential?
    /// 删除凭证
    func deleteCredential(for sourceID: String) throws
}
```

### ScreenPositionStoring

```swift
/// 屏幕位置记忆存取接口
protocol ScreenPositionStoring {
    /// 保存指定场景的屏幕位置
    func savePosition(for environmentID: String, position: ScreenPosition, angle: ViewAngle) async
    /// 读取指定场景的屏幕位置
    func loadPosition(for environmentID: String) async -> SavedScreenPosition?
}
```

---

## 接口与模块的绑定关系总览

| 接口 | 定义在 | 实现方 | 调用方 |
|---|---|---|---|
| `PlaybackControlling` | PlaybackCore/Ports | MPVPlayerAdapter | PlayerUI |
| `FrameOutput` | PlaybackCore/Ports | WindowVideoView 或 VideoTextureUpdater | PlaybackCore |
| `MediaProfileDetecting` | PlaybackCore/Ports | PlayerUI | PlaybackCore |
| `PlaybackEventListening` | PlaybackCore/Ports | PlayerUI | PlaybackCore |
| `SceneStateProviding` | SpatialScene/Ports | SpatialScene 实现 | PlayerUI |
| `SceneRendering` | SpatialScene/Ports | SpatialScene 实现 | PlayerUI |
| `PlaybackModeManaging` | PlayerUI/Ports | PlayerUI 内部实现 | PlaybackModeSwitcher / DecidePlaybackModeUseCase |
| `SceneManaging` | SpatialScene/Ports | SpatialScene 实现 | PlayerUI（SceneSwitcherView + SceneSelectorView） |
| `FileProviding` | FileBrowsing/Ports | FileBrowsing 实现 | App（AppCoordinator / 入口层） |
| `DataSourceConnecting` | FileBrowsing/Ports | SMB/WebDAV/Local 各自实现 | FileBrowsing 内部 |
| `ProgressStoring` | Persistence/Ports | SwiftDataStore | PlaybackCore |
| `PreferencesStoring` | Persistence/Ports | UserDefaultsStore | PlayerUI + Settings |
| `CredentialStoring` | Persistence/Ports | KeychainStore | FileBrowsing |
| `ScreenPositionStoring` | Persistence/Ports | SwiftDataStore | SpatialScene |

> **原则**：接口定义在**被调用方**的 Domain/Ports 目录下，由被调用方的 Adapters 实现，注入到调用方使用。依赖始终指向 Domain 层。
