# Phase 5：表冠真机事实（实验）

[overview](overview.md)

## Goal

裁决两个文档未回答的问题：visionOS 27 上空间与窗口共存时表冠单按的行为；旋转到沉浸量下限的系统行为与 `onImmersionChange` 送达可靠性。

## Changes

只加取证探针，不改产品行为。沉浸空间挂 `onImmersionChange` 探针记录 amount 序列；表冠按压场景由佩戴者执行，探针与录屏取证。

## Verification

证据文件落 TestEvidence；结论回填 overview 的 Constraints 与 phase-8。
