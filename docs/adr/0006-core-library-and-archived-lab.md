# ADR-0006：PlaybackCore 成为纯 library，Lab 归档

- 状态：accepted
- 日期：2026-07-14
- 取代：ADR-0004 与 ADR-0005 中把 Playback Lab 作为核心 L2 或完成条件的部分

## 背景

验证 App 已完成播放链路和 RealityKit 组装探索，但其窗口、空间呈现和产品时态不属于播放核心。继续共同维护会让核心规格、App Adapter 与产品前端出现多个真相源。

## 决策

PlaybackCore 仓库只发布 library，拥有 Media Session、Provider、sample、audio、renderer graph、控制和诊断。所有 App target、UI、空间呈现、运行脚本、设备证据与客户端回归模型移出本仓库。

原验证 App 作为只读历史快照归档，不进入当前构建或验收。Enchron 直接为 PlaybackCore 实现新的 App Adapter。

## 后果

- PlaybackCore 的完成条件只由 library 接口、核心测试和独立低层 probe 证明。
- 可见画面、可听输出、RealityKit、窗口、空间形态和产品交互由消费方验证。
- 核心不得再次增加 App target 或客户端状态模型。
