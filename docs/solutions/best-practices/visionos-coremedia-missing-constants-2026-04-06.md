---
title: visionOS SDK 缺少 Dolby Vision CoreMedia 常量
date: 2026-04-06
category: docs/solutions/best-practices/
module: App
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - 在 visionOS 平台访问 CMFormatDescription extensions 中的 Dolby Vision 配置时
  - code review 建议将字符串字面量替换为公开 CoreMedia 常量时
  - 跨平台（iOS / visionOS）共享 AVFoundation 元数据检测代码时
tags:
  - visionos
  - coremedia
  - dolby-vision
  - platform-availability
  - avfoundation
  - hdr-detection
---

# visionOS SDK 缺少 Dolby Vision CoreMedia 常量

## 背景

在 visionOS 平台使用 AVFoundation 检测视频 HDR 类型时，需要访问 `CMFormatDescription` extensions 字典来判断是否存在 Dolby Vision 配置。

iOS 14+ 的 CoreMedia framework 提供了公开常量 `kCMFormatDescriptionExtension_DolbyVisionConfiguration`，可通过编译器验证的方式访问该字段。code review 流程可能会建议将字符串字面量 `"DolbyVisionConfiguration"` 替换为此常量以获得更好的类型安全性。

然而，该常量在 visionOS SDK 中不存在，替换后会导致编译失败。

## 指导原则

在 visionOS 目标中，继续使用字符串字面量 `"DolbyVisionConfiguration"` 访问 `CMFormatDescription` extensions 字典，并加注释说明原因。不要引入 `#if os(iOS)` 条件编译或 `@available` 注解来绕过——这会增加代码复杂度，而字符串键本身在 CoreMedia 运行时中是稳定的。

```swift
// visionOS 上的正确做法：
if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
    // Note: kCMFormatDescriptionExtension_DolbyVisionConfiguration is not available
    // on visionOS SDK (exists in iOS 14+ CoreMedia but absent from visionOS headers).
    // The raw string key is stable in CoreMedia's internal representation and works
    // at runtime on visionOS.
    if let dvInfo = extensions["DolbyVisionConfiguration"] {
        _ = dvInfo
        return .dolbyVision
    }
}

// 不要这样做（visionOS 编译失败）：
// if let dvInfo = extensions[kCMFormatDescriptionExtension_DolbyVisionConfiguration as String] {
//     return .dolbyVision
// }
```

## 为何重要

- **编译安全**：使用不存在的 SDK 常量会导致 `"Cannot find in scope"` 编译错误，阻断构建。
- **运行时正确性**：字符串键 `"DolbyVisionConfiguration"` 是 CoreMedia 内部字典的稳定键名，与常量底层值一致，运行时行为相同。
- **code review 陷阱**：自动化 review 工具或人工 review 者可能对 iOS 代码库更熟悉，会建议使用公开常量替换字符串字面量，但该建议在 visionOS 上不可行。需要在代码注释中明确说明，避免 review 往返。

## 适用场景

- 编写或审查访问 `CMFormatDescriptionGetExtensions` 返回字典的 visionOS 代码时
- 任何在 iOS 和 visionOS 之间共享的 AVFoundation 元数据检测逻辑
- code review 建议将 Dolby Vision 相关字符串字面量替换为公开常量时

## 示例

**受影响文件**：`XrPlayer/App/MediaProfilePrefetchService.swift`，`detectHDRType` 方法。

当前实现（正确）：

```swift
private static func detectHDRType(
    from formatDescriptions: [CMFormatDescription]
) -> PlaybackCoreDomain.HDRType {
    guard let desc = formatDescriptions.first else { return .sdr }

    // Check Dolby Vision via format description extensions.
    // Note: kCMFormatDescriptionExtension_DolbyVisionConfiguration is not available on visionOS,
    // so we use the raw string key which CoreMedia recognizes internally.
    if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
        if let dvInfo = extensions["DolbyVisionConfiguration"] {
            _ = dvInfo
            return .dolbyVision
        }
    }
    // ...
}
```

若误将字符串替换为常量：

```swift
// 编译错误：Cannot find 'kCMFormatDescriptionExtension_DolbyVisionConfiguration' in scope
if let dvInfo = extensions[kCMFormatDescriptionExtension_DolbyVisionConfiguration as String] {
```

## 相关

- `docs/solutions/best-practices/mpv-video-metadata-detection-2026-04-06.md` — mpv 路径的 HDR 检测实践（与本文档覆盖的 AVFoundation metadata/reference 路径互补）
