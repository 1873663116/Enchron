# Enchron 术语

本文定义在 Enchron 中容易与相近概念混淆的特有名词。

## 播放与媒体

**Playback Presentation**：视频在产品中的呈现位置。它与解释媒体画面的 Media Format 是不同概念。
**Media Format**：用户要求 Enchron 如何解释媒体画面。它不表示视频当前呈现在哪里，也不是来源媒体自身声明的 Format Description。
**Format Description**：一条媒体流向解码器声明的技术事实，包括编码、尺寸、色彩解释，以及立体与动态范围的配置。它由来源媒体决定，不随用户偏好改变。
**Custom Angle**：Enchron 将矩形全景画面按 180° 至 360° 的水平覆盖角解释。它不表示鱼眼镜头映射。

**Media Library**：Enchron 管理的虚拟媒体分类。它保存对媒体的组织和引用，不拥有来源媒体。
**Library Folder**：Media Library 中由用户管理的虚拟分类容器。它不是本地文件系统或远程服务中的目录。
**Source Directory**：本地文件系统或远程服务实际拥有的目录。它不属于 Enchron 的虚拟媒体分类。

**File Source**：直接提供目录结构与文件字节流的媒体来源，如本地、SMB、WebDAV。它不提供媒体实体、元数据或服务器端用户状态。
**Media Byte Stream**：把一个来源媒体表达为可按字节区间读取的流。它只回答长度与指定区间的字节，不解释容器内容，也不代表提供它的来源。

**Emby Source**：提供媒体实体、元数据与服务器端用户状态的媒体服务器来源。它不是 File Source；其媒体流由系统网络库读取，再经 Media Byte Stream 交给播放核心。

**Media Reference**：从 Media Library 指向来源媒体的持久引用。它是访问入口，不是底层媒体的身份。
**Media Identity**：Enchron 用于判断不同入口是否指向同一底层媒体的稳定身份。它独立于 Media Reference。
**Content Revision**：同一 Media Identity 对应内容的版本凭据。它用于区分媒体身份未变但内容已经变化的情况。
**Media Source Information**：同一 Content Revision 的来源媒体所具有的可持久技术事实。它不是实时读取状态，也不是用户选择的 Media Format。

**Playback Collection**：用户开始播放时，本次连续播放可以包含媒体的范围。它不是已经生成的播放顺序。
**Playback Queue**：从 Playback Collection 生成的本次播放顺序。它与之后继续变化的浏览结果分离。
**Persistent Viewing State**：Enchron 为同一 Media Identity 保存的可恢复位置或已看完状态。它不是通用观看历史。
**Viewing State Authority**：一次播放会话的观看状态权威，取值为 Enchron 持久化或媒体服务器之一。它决定播放结束时进度与观看状态写向何处。

## 空间环境

**Environment**：Enchron 提供的一个稳定观影场景身份。它与场景当前采用的视觉变化分离。
**Environment Effect**：同一 Environment 内可变化的视觉表现。它不形成新的 Environment 身份。
**Environment Context**：当前是否有一个 Environment 处于活动状态，以及该场景当前采用什么 Environment Effect。它不是 Playback Presentation。
