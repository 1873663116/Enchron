# Phase 2 产出：战术领域模型

> 本文档定义各限界上下文内部的实体、值对象和聚合。严格遵循 DDD 原则：**不包含任何数据库字段、API 格式或 UI 细节**，只表达业务语义。

---

## 🎬 PlaybackCore 播放核心

### 聚合：PlaybackSession（聚合根）

一次完整的播放生命周期。从"用户选择文件开始播放"到"播放结束或用户退出"。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `PlaybackSession` | 一次播放会话的完整生命周期管理 |
| 值对象 | `PlaybackState` | 当前状态：播放中/暂停/缓冲中/已停止 |
| 值对象 | `PlaybackSpeed` | 当前倍速（0.25x ~ 5.0x） |
| 值对象 | `PlaybackPosition` | 当前播放位置（分:秒）和总时长 |
| 值对象 | `MediaProfile` | 视频画面特征：投影类型 + HDR 类型 + 分辨率 |
| 实体 | `MediaFile` | 当前播放的媒体文件（URL + 格式信息） |
| 实体 | `AudioTrack` | 可选音轨（ID + 语言标签） |
| 实体 | `SubtitleTrack` | 可选字幕轨（ID + 语言标签） |

#### MediaProfile 值对象组成

| 子值对象 | 可选值 |
|---|---|
| `ProjectionType` | 平面 / SBS 左右 / OU 上下 / 360° 全景 / 180° VR / 鱼眼 |
| `HDRType` | SDR / HDR10 / 杜比视界 / HLG |
| `Resolution` | 标清 / 高清 / 4K / 8K / 其他 |

**业务规则**:

- 一个 PlaybackSession 同一时刻只能关联一个 MediaFile
- 切换选集中的视频 = 结束当前 Session 并创建新 Session
- Session 结束时必须触发进度保存事件
- 倍速切换不创建新 Session
- MediaProfile 在文件打开时自动识别（读取元数据 + 文件名匹配），允许用户手动覆盖

### 领域事件

| 事件 | 触发时机 |
|---|---|
| `PlaybackStarted` | 视频开始播放 |
| `PlaybackPaused` | 播放暂停 |
| `PlaybackResumed` | 从暂停恢复 |
| `PlaybackEnded` | 播放完毕或用户退出 |
| `TrackSwitched` | 音轨或字幕轨切换 |
| `SpeedChanged` | 倍速变更 |
| `ProgressUpdated` | 播放位置变化（定期触发，用于进度保存） |
| `MediaProfileDetected` | MediaProfile 识别完成（通知 PlayerUI 决策播放模式） |

---

## 🎛️ PlayerUI 播放界面

### 聚合 1：GestureDisambiguator（内部子组件）

手势消歧状态机，负责在 200ms 观察窗口内判断用户意图。

| 类型 | 名称 | 说明 |
|---|---|---|
| 组件 | `GestureDisambiguator` | 消歧状态机 |
| 值对象 | `GestureType` | 识别结果：单次捏合/双击/长按/拖拽 |
| 值对象 | `GesturePhase` | 当前阶段：等待中/观察窗口/已确认 |
| 值对象 | `PlaybackCommand` | 翻译后的播放控制指令 |

**业务规则**:

- 首次捏合触发后进入 200ms 观察窗口
- 窗口内第二次捏合 → 双击（播放/暂停）
- 窗口内持续保持 → 长按（2.0 倍速）
- 长按后水平拖动 → 拖拽（进度条）
- 以上均不满足 → 单次捏合（唤出主菜单）

### 聚合 2：PlaybackMode（播放模式决策）

根据 MediaProfile + 场景状态决定渲染路径。

| 类型 | 名称 | 说明 |
|---|---|---|
| 值对象 | `PlaybackMode` | 当前模式：窗口/沉浸场景/全景 |
| 值对象 | `RenderingPath` | 渲染路径：SwiftUI 窗口 / RealityKit 虚拟屏幕 / RealityKit 全景球体 |

**决策规则**:

- 全景视频（360°/180°/鱼眼）→ 全景模式，进入沉浸空间但不加载虚拟场景
- 非全景视频 + 当前已在虚拟场景中 → 沉浸场景模式
- 非全景视频 + 当前未在虚拟场景中 → 窗口模式
- 用户可手动覆盖自动决策（例如在窗口模式下强制切换到沉浸场景）

### 领域事件

| 事件 | 触发时机 |
|---|---|
| `GestureRecognized` | 消歧完成，携带确认的 GestureType |
| `CommandIssued` | 手势被翻译为 PlaybackCommand 并发出 |
| `PlaybackModeDecided` | 播放模式决策完成 |
| `RenderingPathSwitched` | 渲染路径发生切换 |

---

## 📁 FileBrowsing 文件浏览

### 聚合 1：DataSource（聚合根）

一个数据源代表一个文件来源（本地存储或远程服务器）。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `DataSource` | 文件来源的抽象（本地/SMB/WebDAV） |
| 值对象 | `SourceType` | 类型：本地文件系统/Apple 相册/SMB/WebDAV |
| 值对象 | `ConnectionInfo` | 远程连接信息（地址、端口、协议） |

### 聚合 2：MediaFolder（聚合根）

一个可浏览的文件夹。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `MediaFolder` | 一个文件夹目录 |
| 实体 | `MediaFile` | 文件夹内的媒体文件（文件名、大小、修改时间、格式类型） |
| 值对象 | `SortCriteria` | 排序方式：按名称/修改时间/大小（升序降序） |
| 值对象 | `FileFilter` | 过滤条件：只显示可播放格式 |

**业务规则**:

- 不可播放格式的文件不出现在列表中
- 排序方式可切换，切换后立即生效
- 远程文件夹的内容需要通过网络获取，有加载状态

---

## 🌌 SpatialScene 空间场景（独立生命周期）

### 聚合：VirtualEnvironment（聚合根）

用户当前所处的虚拟空间环境。场景可以在不播放视频的情况下独立存在和切换。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `VirtualEnvironment` | 一个 3D 虚拟场景（如影院/太空主题），由 Reality Composer Pro 制作 |
| 实体 | `VirtualScreen` | 场景中的视频显示平面（沉浸场景模式使用） |
| 实体 | `PanoramaSphere` | 全景投影球体/半球体（全景模式使用，不加载虚拟场景） |
| 值对象 | `ScreenPosition` | 虚拟屏幕的远近距离和垂直高度 |
| 值对象 | `ViewAngle` | 虚拟屏幕的 X 轴旋转角度 |
| 值对象 | `ScreenSize` | 虚拟屏幕的尺寸 |
| 值对象 | `SceneActiveState` | 当前场景是否活跃（供 PlayerUI 查询） |

**业务规则**:

- 场景的打开/关闭完全独立于视频播放行为
- 一个 VirtualEnvironment 同一时刻只有一个 VirtualScreen
- 每个场景的屏幕位置和视角旋转独立记忆
- 播放开始时可能触发环境光变化（MVP 可缺省）
- PanoramaSphere 在全景模式下独立于 VirtualEnvironment 使用

### 领域事件

| 事件 | 触发时机 |
|---|---|
| `EnvironmentActivated` | 用户进入了虚拟场景 |
| `EnvironmentDeactivated` | 用户退出了虚拟场景 |
| `EnvironmentSwitched` | 用户切换到另一个虚拟场景 |
| `ScreenPositionAdjusted` | 用户调节了屏幕远近或高度 |
| `ViewAngleAdjusted` | 用户调节了视角旋转角度 |

---

## 💾 Persistence 持久化

### 聚合 1：PlaybackProgress（聚合根）

一条播放进度记录。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `PlaybackProgress` | 单个媒体文件的播放进度记录 |
| 值对象 | `FileIdentifier` | 文件唯一标识（路径/URL 组合） |
| 值对象 | `ProgressPosition` | 记录的播放位置（分:秒） |
| 值对象 | `RecordTimestamp` | 记录的时间戳（用于过期清理） |

**业务规则**:

- 超过 5 天的记录自动清理
- 同一文件的进度被覆盖更新，不产生多条记录

### 聚合 2：UserPreferences（聚合根）

用户的全局偏好设置。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `UserPreferences` | 用户全局设置 |
| 值对象 | `ResumePolicy` | 进度恢复策略：每次询问/总是恢复/总是从头 |
| 值对象 | `DefaultEnvironment` | 默认加载的虚拟场景标识 |

### 聚合 3：SavedScreenPosition（聚合根）

每个虚拟场景独立的屏幕位置记忆。

| 类型 | 名称 | 说明 |
|---|---|---|
| 聚合根 | `SavedScreenPosition` | 某个虚拟场景的屏幕位置记录 |
| 值对象 | `EnvironmentIdentifier` | 虚拟场景标识 |
| 值对象 | `ScreenPosition` | 记忆的远近距离和垂直高度 |
| 值对象 | `ViewAngle` | 记忆的视角旋转角度 |
