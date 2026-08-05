# Enchron 真机 XCTest 临时迁移清单

本文件只保存尚未迁入 [`SCENARIOS.md`](SCENARIOS.md) 当前共享真机场景的一次性工作。它不是产品规格、回归场景目录、Test Plan 或运行证据；迁移完成一项就删除对应记录，全部完成后删除本文件。

迁移有效断言时遵守 [`AGENTS.md`](AGENTS.md)。物理 Vision Pro 前置条件或真实协议设施缺失时保留明确缺口，不用任意设备内容、假服务器、autoplay 输入或只证明控件存在的断言代替。

## 播放与媒体矩阵

- 为 Window 基础播放闭环建立能够确定性延迟首帧、同时保持生产播放管线与正常 Media Library 入口的启动变体；加载机械状态、加载阶段画面和首帧后画面必须共同判定。
- 将登记媒体矩阵拆成每个媒体独立执行的方法，准确声明支持、预检失败、字幕、声音和感知边界；移除生产 Media Library 任意遍历与笼统接受 unsupported codec 的旧诊断。
- 收束 `VisionProDeviceAcceptanceUITests`：保留一个最小外置麦克风、时间基准和分析链校准工具，以及仍有开放问题所有者的诊断；基础播放、Seek、AAC、空间往返和重复 tone 实验退出该文件。

## 来源与 Library Folder

- Photos 使用稳定登记素材、可处理的系统授权状态和正常 Media Library；不得清空已有 Media Library 或任意选择 Photos 中的第一个项目。
- Library Folder 管理补充物理 Vision Pro 上的 App 进程重启后层级与名称恢复。快速持久化合同已经存在；UI fixture 目前只覆盖同进程公开管理操作。
- WebDAV 与 SMB 分别建立真实协议设施、固定目录、登记远程媒体和安全凭据注入。每种来源覆盖认证、只读 Source Directory 导航、Media Reference 建立、播放与 App 重启解析；SMB 账号认证与 Guest 分开执行。

## Settings

- Resume Playback、End of Playback、Default Speed 与 Controls Auto-Hide 分别建立设置驱动场景变体。Default Speed 在快速层穷举后轮换真机边界与代表值，其它设置逐个执行全部选项。
- Thumbnail Cache 与 Playback Progress 清理进入对应数据场景；Privacy Notice、Version & Build、Support & Feedback 和 Open-source Licenses 使用快速 UI 测试。

## Environment 与 Docked Placement

- 当前四个稳定 Environment 的生产入口完成后，为每个 identity 接入 Day/Night，并验证 placement 按 identity 隔离、同一 identity 的 Day/Night 共享。保留现有跨 Media Session、App 进程重启与 Restore Defaults 覆盖。
