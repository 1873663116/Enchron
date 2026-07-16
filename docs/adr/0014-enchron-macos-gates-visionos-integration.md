# ADR-0014：Enchron macOS App 先于 visionOS 产品集成证明播放

- 状态：accepted
- 日期：2026-07-16

## 背景

PlaybackCore 从旧回调式 enqueue 迁移到 AVFoundation Receiver API 后，library build 与单元测试通过，但原 Verify App 的 macOS 真实播放闭环没有随 Enchron 保留下来。visionOS 产品同时包含来源解析、PlaybackRuntime、SwiftUI、RealityKit scene 和设备差异，直接在该层首验会把核心失败与产品失败混在一起。

## 决策

Enchron 同时维护 macOS App 与 visionOS App。macOS App 是 L2 验证宿主，并按顺序提供 Core scenario 与 App Adapter scenario：前者直接连接 PlaybackCore，后者连接生产 `PlaybackRuntime`。两者共享真实 fixture、RealityKit consumer、节点 7–9 断言和控制矩阵。

只有 PlaybackCore L1、macOS Core scenario 与 macOS App Adapter scenario 全部通过，才进入 visionOS Simulator；Simulator 通过后才进入 L3 Vision Pro。

## 考虑过的替代方案

- 只在 PlaybackCore 仓库恢复独立 Verify App：会重新建立与 Enchron 分离的 App 组装真相源。
- 直接使用 visionOS App 验证核心：失败变量过多，且设备与 Simulator 成本更高。
- 只保留低层 probe：无法证明真实 RealityKit consumer、音频和产品 adapter。

## 后果

- macOS App 与 visionOS App 共享 Enchron 的生产 adapter 和可移植 surface，不建立平行前端。
- PlaybackCore 回归先在 macOS Core scenario 收敛；产品接入差异在 App Adapter scenario 收敛。
- visionOS Simulator 不再承担核心首验；Vision Pro 只承担设备独有事实和最终验收。
