# ADR 0020：Media Byte Stream 是远程来源唯一的字节入口

状态：Accepted

日期：2026-08-16

## 决策

所有远程来源的字节经由 MediaSource 拥有的 Media Byte Stream 进入播放，通道是一个本机回环 HTTP 端点。本地文件不经过它，播放核心直接以文件路径打开。

播放核心继续只接收一个可打开的地址，不认识来源类型。类型上的约束设在 PlaybackFeature：播放入口只接受由 Media Byte Stream 发出的句柄，裸地址传不进来。

字节来源协议由 MediaSource 定义，成员为长度（可为未知）、能否跳转、是否实时、建议缓冲深度、按区间读取。MediaLibrary 与 Emby 各自提供实现。

## 为什么是回环 HTTP 端点

播放路径上有两个独立的字节消费者。FFmpeg 负责解封装。AVFoundation 另开一次容器读取，取它自己解析出的 Format Description，用来补 FFmpeg 重建不出的信号（MV-HEVC 的层配置、Apple Immersive 投影标记）。

AVFoundation 只接受两种字节来源：真实的 URL，或自定义 scheme 加资源加载委托。回环 HTTP 端点是唯一无需额外适配层即可同时服务两个消费者的形态，因此 Container Index Cache 与预读挂在这一层时对两者同时生效。

## 考虑过的替代方案

**自定义 AVIOContext。**把字节源接进 FFmpeg 的自定义 I/O 回调，删掉回环服务器。它无法统一入口，因为 Emby 直连仍需 FFmpeg 原生 HTTP 处理重定向与认证，否则要在 URLSession 上重写一遍 HTTP 客户端语义。它还会让 AVFoundation 那一路失去可读的源，必须新增资源加载委托。其回调在解封装线程上同步执行，桥接到异步的 URLSession 与 SMB 客户端会引入死锁面。收益仅为省去一次本机内存拷贝，而实测表明打开耗时由请求数与每请求 330 至 520 毫秒的往返主导，与该拷贝无关。

**FFmpeg 原生 SMB 与 NFS 协议。**当前 vendored 的 FFmpeg 只编入 file、http、https、crypto、data 五种协议，走这条路要重建整个 xcframework，并引入第三方库的许可与审核论证。同样使 AVFoundation 那一路失去可读的源。

## 后果

- 回环端点需支持长度未知的来源，此时改用分块传输并声明不可跳转。因此桥接层中为绕开不合规服务端而设的 HTTP 特殊处理（强制声明可跳转、连接复用、前置长度探测、end_offset）随之删除，回环端点由本仓库自身保证合规。
- 游戏串流一类的实时交互源可以作为不可跳转、零缓冲的字节来源接入，但其输入回传通道不属于本管线。
- SMB 是唯一需要显式连接管理的来源，一台服务器一条连接，浏览与播放共用。WebDAV 与 Emby 的连接由系统网络库按主机自动池化。
- 证书信任成为单一策略，所有网络请求共用。Emby 字节改走系统网络库后，播放与浏览不再各自判断证书。
