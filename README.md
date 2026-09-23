# Enchron

简体中文 | [English](README.en.md)

Enchron 是面向 Apple Vision Pro 的媒体播放器。应用可在窗口和沉浸空间中播放视频，支持本地文件、SMB、WebDAV 和 Emby 媒体库。

## 状态

Enchron 正在准备 TestFlight 外部测试。功能、兼容性和发布方式可能变化。

## 功能

- 在窗口、停靠屏幕和沉浸式环境中播放视频。
- 浏览本地媒体库，或连接 SMB、WebDAV 和 Emby 服务器。
- 控制播放、切换字幕和音轨。
- 使用 AVFoundation 进行硬件加速解码和渲染。HDR10、HLG 和杜比视界的播放能力取决于设备及媒体格式。
- 使用 FFmpeg 解封装常见媒体格式。H.264、HEVC 和 AV1 等编码格式的播放能力取决于设备；Apple Vision Pro（M5）支持 AV1。

## 构建

本项目需要 Xcode 27.0 与 visionOS SDK。`Packages/PlaybackCore` 依赖未纳入 Git 的 `PlaybackFFmpeg.xcframework`。在克隆后的仓库根目录运行以下命令以准备该依赖：

```sh
Scripts/provision_vendored_ffmpeg.sh
```

该脚本会构建 FFmpeg，或在传入另一个已具备该二进制的工作副本路径时复用其中的文件。构建与验证入口位于 `Scripts/` 和 `Regression/`。项目约束、模块所有权和测试协议分别见 [`ARCHITECTURE.md`](ARCHITECTURE.md)、[`AGENTS.md`](AGENTS.md) 和 [`Regression/README.md`](Regression/README.md)。

## 隐私与网络

Enchron 不运营媒体服务，也不将媒体、播放历史或远程凭据发送给开发者。应用会直接连接用户配置的服务器。远程凭据保存在当前设备的 Keychain 中。完整说明见 [`PRIVACY.md`](PRIVACY.md)。

为了连接未配置 TLS 的自托管服务器，应用允许明文 HTTP；连接公网地址前，应用会显示凭据可能明文传输的确认提示。可使用 HTTPS 或私有加密网络。

## 开源许可与第三方组件

Enchron 以 Apache License 2.0 发布，许可证文本位于 [`LICENSE`](LICENSE)。第三方组件及其许可证见 [`NOTICE`](NOTICE)，应用内的设置页面也提供相同的许可证信息。

## 外部贡献

目前本项目暂不接受外部贡献。仓库用于源码查阅、构建复现和许可证履行；CI、签名与发布基础设施不向外部开放。
