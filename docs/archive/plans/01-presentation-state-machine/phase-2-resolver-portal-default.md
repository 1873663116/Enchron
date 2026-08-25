# Phase 2：格式应用后的呈现解析改为 portal 默认

[overview](overview.md)

## Goal

应用全景投影不再自动进入 panorama；用户停在 portal，由显式按钮进沉浸。

## Changes

- EffectiveMediaFormatPresentationResolver：panoramic 且当前在主窗口列 → portal（同窗投影切换）；flat 且当前在主窗口列 → window；当前在沉浸列时的格式应用不再可能（phase-3 移除入口后该分支只防御性保留为 unchanged）。
- 删除 `returnToWindowThenEnterPanorama` 分支与 `automaticPanoramaEntryPending` 全部机制。
- 打开媒体时的落地呈现同步遵循 portal 默认：持久化为全景族的媒体落 portal 而非 panorama（冷启动与温启动两条映射都改）。
- 非法边的强制拒绝不在本阶段接入：等 phase-4 把全部入口按钮改到族内目标后，与按钮改动一起落地，保证阶段之间行为完整。

## Data structures

无新增；resolver 返回值枚举瘦身。

## Verification

模拟器套件：resolver 全分支单测改判；自动全景进入的既有测试删除或改判为 portal 落地。
