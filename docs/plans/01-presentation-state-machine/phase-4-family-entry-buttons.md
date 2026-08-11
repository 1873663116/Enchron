# Phase 4：按内容族区分的进沉浸按钮

[overview](overview.md)

## Goal

Window 的进沉浸按钮通往 Dock，Portal 的进沉浸按钮通往 Panorama；跨族入口不存在。

## Changes

- 窗口 chrome 与 deck 的进沉浸动作按 `contentFamily` 解析目标：flat → docked，panoramic → panorama；移除按 `effectiveContentIsPanoramic` 显隐两个按钮的旧逻辑。
- 退出沉浸动作对称：docked → window，panorama → portal（收编 phase-1 策略）。
- accessibility identifier 保持稳定或在特性地图（`.claude/skills/visionpro-xcuitest/features/`）同步更新。

## Data structures

无新增；按钮目标由 phase-1 的族属性推导。

## Verification

模拟器套件：入口解析单测。设备回归（phase-9）走四格子的进出往返。
