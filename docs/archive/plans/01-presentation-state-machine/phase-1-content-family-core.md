# Phase 1：内容族与合法边的类型核心

[overview](overview.md)

## Goal

把 2×2 模型编码为类型，让非法转换在请求入口被集中拒绝，替代散落各处的守卫。

## Changes

- PlaybackPresentation 获得派生属性 `contentFamily`（flat 对 panoramic 的枚举），与既有 `usesMainWindow`/`usesImmersiveSpace` 一起张成 2×2。
- 新增呈现边策略类型：给定（当前呈现，目标呈现）判定边的类别——同族进出沉浸、同窗改投影、自环、非法。策略是纯函数，落在 PlaybackPresentation 定义旁。
- `requestPlaybackPresentation` 在创建 transition 前咨询该策略，非法边抛出带边信息的错误。既有调用方的守卫暂不删除（phase-2 到 4 逐个收编）。

## Data structures

- `PresentationContentFamily`：`flat | panoramic`。
- `PresentationEdge`：`enterImmersive | exitImmersive | projectionSwap | inPlace | illegal` 一类的判别枚举。

## Verification

模拟器套件：新增边策略全矩阵单测（4×4 共 16 组）；既有呈现测试全绿。
