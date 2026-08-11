# Phase 7：横向边实现（重建路线）

[overview](overview.md)

## Goal

window↔docked 与 portal↔panorama 采用重建路线：族内进出沉浸时技术 session 预组装替换（phase-6 已裁决 renderer 跨场景转移不可行），播放位置与状态跨重建保持连续。

## Changes

- 执行器的转换效果收敛到新边集合：族内纵向边（enterImmersive/exitImmersive）与主窗口列投影切换（projectionSwap），按 phase-1 边策略瘦身；对角线路径与相应状态删除。
- 重建期间的用户可见连续性目标：位置、播放/暂停状态、音轨选择跨重建保持；黑场窗口尽可能短。

## Verification

设备：横向边往返的连续性证据（截图序列与探针时间线）；phase-9 矩阵。
