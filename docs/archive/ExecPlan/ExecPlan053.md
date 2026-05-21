# ExecPlan053 — Video Detail Preparation Unblocks First Launch

## Problem

首次 Debug 启动后，点开视频进入详情页时，媒体信息加载可能一直停留在 loading；也可能加载完成后详情页 hover 正常但点击无法触发。两个症状都指向同一风险：详情页准备阶段把生产 mpv 会话提前加载进来，导致 UI 详情流依赖播放器层、mpv control queue 和底层 render 状态。

## Scope

- 详情页准备阶段只解析轻量 metadata，不启动或预加载生产 mpv 会话。
- 确认播放后再通过正常播放启动路径加载 mpv。
- 保留 `PlaybackLaunchCoordinator` 作为详情页和播放启动的单一状态入口。
- 不改动 HDR 诊断、DesignPreview 或播放控件视觉。

## Verification

- `git diff --check`
- `swift test`
- `xcodebuild -project XrPlayer.xcodeproj -scheme XrPlayer -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-XrPlayer-build build`

## Human Regression

- 退出 App 后从 Xcode Debug 冷启动，首次点开本地视频，详情页必须进入可点击 ready 状态。
- 在详情页 ready 后，返回、播放、环境选择和播放模式选择都应能点击。
- 点击播放后再进入播放器，不应要求重启 App 才恢复。
