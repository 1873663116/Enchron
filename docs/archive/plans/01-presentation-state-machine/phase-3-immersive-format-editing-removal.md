# Phase 3：移除沉浸宿主的格式编辑

[overview](overview.md)

## Goal

格式编辑只存在于主窗口列；沉浸空间内的面板不再提供投影与排列的编辑能力。

## Changes

- PlaybackPanel 的 Advanced Settings 宿主（PlayerPanel-VideoFormat-*）在 panorama/docked 下不再渲染格式编辑器；portal 保留（它在主窗口列）。
- 相应的 `launcher.applyFormat` 面板入口按呈现列裁剪；窗口菜单宿主（PlayerUI-VideoFormat-*）不动。
- 面板在沉浸下的 settings 区域收敛为既有的摆位控制。

## Data structures

无新增。

## Verification

模拟器套件：面板宿主按呈现的渲染条件单测。设备回归（phase-9）确认 panorama 下面板无格式区、portal 下有。
