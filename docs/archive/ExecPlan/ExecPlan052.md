# ExecPlan052 — Playback Return Teardown Fix

## Problem

点击播放界面左上角返回后，旧视频会话必须被终止。当前现象说明 UI 已返回浏览器，但底层播放资源仍可能继续占用 mpv/audio/render 路径，并在下一个本地视频准备或加载期间继续播放。

## Scope

- 返回按钮和播放切换路径必须结束旧 `PlaybackSession`。
- mpv stop/cancel 必须让已排队但尚未执行的旧 load 失效。
- 退出播放时释放 mpv/render context 与安全作用域资源。
- 不改动 HDR 诊断功能、不引入第二套播放启动路径。

## Verification

- `git diff --check`
- `swift test`
- `xcodebuild -project XrPlayer.xcodeproj -scheme XrPlayer -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-XrPlayer-build build`

## Human Regression

- 播放视频 A，点击播放界面左上角返回，确认 A 立即停止出声且进度不再推进。
- 选择本地视频 B，在 B 加载期间确认 A 不再继续播放。
- 重复一次准备详情页返回：打开详情页但不确认播放，返回后不应残留预加载 mpv 状态。
