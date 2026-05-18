# QA Report — v3 Batch 3 (G-M)

**Date**: 2026-04-02
**Scope**: G 播放控件 + H 手势 + I 状态管理 + J 错误处理 + K HDR色彩 + L 设置 + M 辅助功能
**Paths**: 33 条
**Method**: 代码结构审计（3 并行 Sonnet agents）

---

## Summary

| Verdict | Count | % |
|---------|-------|---|
| PASS | 21 | 63.6% |
| PARTIAL | 5 | 15.2% |
| FAIL | 7 | 21.2% |
| **Health Score** | **71.2** | |

**Known FAILs confirmed**: G04, H04, J03, K03, L05 (5/7)
**New FAILs**: M03 (VoiceOver), M04 (WorldTracking)
**Known FAILs upgraded**: J01 (PARTIAL, enum exists), L06 (PARTIAL, About exists)

---

## G. 播放控件 (7 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-G01 可变播放速度 | **PASS** | PlaybackSpeed.allCases 10档, speedMenu UI 完整, mpv speed 接线 |
| QA-G02 音轨选择 | **PASS** | PlaybackMenuView "Audio Tracks" section, mpv aid 切换完整 |
| QA-G03 字幕选择+CJK | **PASS** | 字幕面板+sid切换+blend-subtitles=yes+Noto Sans SC 字体 |
| QA-G04 二级时间轴 | **FAIL** | DetailedTimelineGeometry 196行代码孤立, 无任何SwiftUI View消费 (KNOWN_FAIL) |
| QA-G05 逐帧步进 | **PASS** | frame-step/frame-back-step + UI按钮 (backward.frame.fill/forward.frame.fill) |
| QA-G06 选集列表 | **PASS** | playlistMenu 渲染 fileBrowsingViewModel.files, 选择后切换播放 |
| QA-G07 进度条拖拽 | **PASS** | Slider + onEditingChanged seek 接线完整 |

---

## H. 手势交互 (4 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-H01 单次捏合 | **PASS** | DisambiguateGestureUseCase 400ms消歧 → singlePinch → showControls 切换 |
| QA-H02 双次捏合 | **PASS** | doublePinch → pause/resume/replay 三态覆盖 |
| QA-H03 捏合长按 | **PARTIAL** | longPress 200ms→speed=2.0 可用, 但松开硬编码恢复1.0x(不保留用户原速) |
| QA-H04 捏合拖拽 | **FAIL** | MainView .drag case → break 空操作 (KNOWN_FAIL) |

---

## I. 状态管理 (5 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-I01 进度记忆+恢复 | **PASS** | persist-on-teardown→SwiftDataStore + VideoDetailView Resume按钮, 全链路完整 |
| QA-I02 记住选择 | **PASS** | SettingsView Picker 3选项 + UserDefaultsStore 读写 |
| QA-I03 播放结束行为 | **PASS** | keep-open=yes + eof→.ended + arrow.counterclockwise重播图标 |
| QA-I04 自动下一集 | **PASS** | playbackEndBehavior .playNext → nextFileProvider 调用, Settings 3选项 |
| QA-I05 文件列表进度 | **PASS** | FolderListView 橙色圆点 + "Watched XX:XX" 文本, loadProgressForFiles 完整 |

---

## J. 错误处理 (3 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-J01 网络缓冲动画 | **PARTIAL** | PlaybackState.buffering 枚举已定义, 但 MPVPlayerAdapter 从未触发; 有加载ProgressView但基于presentationState非buffering |
| QA-J02 网络断开错误 | **PASS** | onRuntimeError → .failed + lastErrorMessage → Alert 完整 |
| QA-J03 后台静默重连 | **FAIL** | 无 NWPathMonitor/reachability/retry/backoff (KNOWN_FAIL) |

---

## K. HDR / 色彩管理 (4 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-K01 HLG 检测 | **PASS** | arib-std-b67/hlg → .hlg + CAEDRMetadata.hlg 完整 |
| QA-K02 HDR10+ 检测 | **PARTIAL** | hdr10Plus 枚举+检测存在, 但 EDR 降级到 HDR10 路径(Apple无HDR10+ EDR API) |
| QA-K03 HDR/SDR 切换 | **FAIL** | setHDREnabled 后端完整, UI 层零调用 (KNOWN_FAIL) |
| QA-K04 SDR 无 HDR 标签 | **PASS** | hdrTypeLabel(.sdr)="SDR", 不误标 |

---

## L. 设置与偏好 (6 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-L01 恢复播放策略 | **PASS** | Picker + UserDefaultsStore + onAppear还原, 全链路 |
| QA-L02 播放结束行为 | **PASS** | Picker stop/repeatOne/playNext + 持久化 |
| QA-L03 默认播放速度 | **PASS** | Picker allCases + 新视频启动应用默认速度 |
| QA-L04 服务器管理删除 | **PASS** | destructive Button + removeDataSource + Keychain删除 (但按钮24pt) |
| QA-L05 远程缓存清理 | **FAIL** | SettingsView 零缓存清理UI (KNOWN_FAIL) |
| QA-L06 关于页面 | **PARTIAL** | Section("About") 存在, Build号动态读取, 但Version硬编码"0.1" |

---

## M. 辅助功能与平台合规 (4 paths)

| QA Path | Verdict | Key Finding |
|---------|---------|-------------|
| QA-M01 交互目标≥60pt | **PARTIAL** | 主按钮72pt✅, 逐帧60pt✅, 但关闭48pt❌/删除24pt❌/列表行高不保证❌ |
| QA-M02 Ornament合规 | **PASS** | 唯一ornament锚定.scene(.bottom), 不遮挡视频 |
| QA-M03 VoiceOver标签 | **FAIL** | 全项目零 accessibilityLabel/accessibilityHint (新发现) |
| QA-M04 WorldTracking | **FAIL** | 零 WorldTrackingProvider/ARKitSession, 实体用相对坐标非世界锚定 (新发现) |

---

## New Issues (Batch 3)

| # | Severity | Issue | Location |
|---|----------|-------|----------|
| ISSUE-010 | Medium | longPress 松开硬编码恢复1.0x, 不保留用户原速 | MainView.swift:141-146 |
| ISSUE-011 | **High** | 全项目零 VoiceOver accessibilityLabel 覆盖 | 全部 View 文件 |
| ISSUE-012 | **High** | 无 WorldTrackingProvider/ARKitSession, 沉浸模式无世界空间锚定 | SpatialScene/ |
| ISSUE-013 | Low | About 页 Version 硬编码 "0.1" | SettingsView.swift:55 |

---

## T1.1 Overall (3 Batches Combined)

| Batch | Paths | PASS | PARTIAL | FAIL | DEFERRED | Health |
|-------|-------|------|---------|------|----------|--------|
| 1 (ABC) | 12 | 7 | 4 | 0 | 1 | 81.8 |
| 2 (DEF) | 14 | 6 | 5 | 3 | 0 | 60.7 |
| 3 (G-M) | 33 | 21 | 5 | 7 | 0 | 71.2 |
| **Total** | **59** | **34** | **14** | **10** | **1** | **70.7** |

Formula: Health = (PASS + PARTIAL×0.5) / (Total − DEFERRED) × 100
