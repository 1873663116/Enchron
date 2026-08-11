# Phase 6：renderer 跨场景重绑定探针（实验）

[overview](overview.md)

## Goal

裁决横向边能否不重建 session：同一技术 session 的 renderer，在旧场景 entity 摘除组件后，于新场景 entity 上重建组件能否继续出帧。

## Changes

一次性探针（DEBUG 通道或独立验证入口），portal→panorama→portal 往返，记录帧连续性、组件渲染状态、renderer 状态。探针代码不并入产品路径。

## Verification

录屏与诊断串证据；结论二选一回填 phase-7：转移实现或保留重建实现。
