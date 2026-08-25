# Phase 9：回归矩阵与死路径清理

[overview](overview.md)

## Goal

四格子全边覆盖的设备回归；删除新模型下不可达的机制与状态。

## Changes

- `playback_mode_matrix.py` 的路径集合按新边集合更新。
- 清理：自动全景进入残留、对角线转换分支、沉浸宿主格式编辑的死代码。
- 特性地图（mode-transitions.md、format-editing.md）更新为新模型的到达路径与终态。

## Verification

矩阵全 PASS（像素佐证）；模拟器套件全绿；同窗重建累积压力（≥5 次循环）纳入矩阵或单独 cell。
