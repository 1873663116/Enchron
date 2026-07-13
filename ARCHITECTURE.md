# Enchron 架构

Enchron 是最终产品的 composition root。它组合外部 PlaybackCore、文件来源、SwiftUI 前端、持久化和 Xrplay_scene 导出的 RealityKit 内容；本仓库不拥有解封装、sample 组装、音视频时间线或 renderer graph。

```text
FileBrowsing -> PlaybackLaunchCoordinator -> Playback App Adapter -> PlaybackCore
                                               |                    |
                                               v                    v
PlayerUI <-------------------------- state / controls     video renderer
                                               |                    |
                                               v                    v
Persistence                              SpatialScene <- RealityKitContent
```

## 所有权

- `FileBrowsing`：本地、Photos、SMB、WebDAV 的浏览、授权和来源事实。
- `PlaybackLaunchCoordinator`：唯一产品播放启动入口，协调窗口、恢复位置和来源生命周期。
- `Playback App Adapter`：把 PlaybackCore 的控制、状态和 renderer 映射到 App；不复制核心状态机。
- `PlayerUI`：播放控件、时间轴、用户覆盖和 `PlaybackMode` 决策。
- `SpatialScene`：Window、沉浸环境、固定屏幕和 Panorama 的 App 侧呈现与生命周期。
- `Persistence`：进度、偏好、凭证和屏幕位置。
- `PlaybackCore`：相邻独立仓库，独占媒体会话、轨道、sample、时间线、renderer 和诊断事实。
- `Xrplay_scene`：相邻独立仓库，独占 RCP3 场景创作并导出 RealityKitContent / USD。

## 不变量

- 产品播放只经过 `PlaybackLaunchCoordinator`，一个产品会话只对应一个 PlaybackCore Media Session。
- Enchron 不定义 `PlaybackEngine` 路由，不包含 mpv adapter，也不维护第二套播放状态机。
- PlaybackCore 报告媒体事实；`PlayerUI` 决定呈现模式；`SpatialScene` 执行空间呈现。
- Xrplay_scene 只交付场景内容，不接收视频纹理、不控制播放。
- 跨仓事实只在所有者仓库定义；本仓只记录依赖版本和产品侧组装结果。

## 当前迁移状态

漂亮前端、FakeApp、文件浏览、持久化和场景加载仍在本仓。旧 `XrPlayer/PlaybackCore`、MPVKit、Metal texture bridge 和 mpv 诊断面等待外部 PlaybackCore 的 App Adapter vertical slice 建立后删除；它们不是当前架构真相。
