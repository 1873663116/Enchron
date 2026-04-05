---
title: "Xcode 15+ Asset Catalog Color Sets conflict with manual Color extension"
date: 2026-04-05
category: build-errors
module: Shared/Extensions
problem_type: build_error
component: tooling
symptoms:
  - "error: invalid redeclaration of 'enchronSurface' — 9 identical errors for each Color Set"
  - "SwiftCompile fails on Color+DesignTokens.swift with all 9 static let properties"
root_cause: config_error
resolution_type: code_fix
severity: medium
tags: [xcode, asset-catalog, color-set, swiftui, generated-asset-symbols, visionos]
---

# Xcode 15+ Asset Catalog Color Sets 与手动 Color extension 冲突

## 问题
在 Asset Catalog 中创建命名 Color Sets 后，同时在 `Color` extension 中定义同名 `static let` 属性会导致 "invalid redeclaration" 编译错误。9 个 Color Set 产生 9 个相同的编译错误。

## 症状
- `error: invalid redeclaration of 'enchronSurface'`（及其他 8 个颜色）
- 仅在 Xcode build 中出现（SPM build 不受影响，因为 SPM 不处理 Asset Catalog）
- 错误指向 `Color+DesignTokens.swift` 中的每个 `static let` 声明

## 尝试过但无效的方法
- 在 `Color` extension 中使用 `static let enchronSurface = Color("enchronSurface", bundle: .main)` — 与 Xcode 自动生成的符号冲突

## 解决方案
删除手动的 `Color+DesignTokens.swift` extension 文件。Xcode 15+ 自动从 Asset Catalog 的 Color Sets 生成 type-safe 访问器。

**之前（冲突）：**
```swift
// Color+DesignTokens.swift — 手动编写，会冲突
extension Color {
    static let enchronSurface = Color("enchronSurface", bundle: .main)
    // ... 其他 8 个
}
```

**之后（正确）：**
只需在 Asset Catalog 中创建 Color Sets，Xcode 自动在 `DerivedSources/GeneratedAssetSymbols.swift` 中生成：
```swift
// 自动生成 — 无需手动编写
extension Color {
    static var enchronSurface: Color { .init(resource: .enchronSurface) }
}
extension ColorResource {
    static let enchronSurface = ColorResource(name: "enchronSurface", bundle: resourceBundle)
}
```

使用方式完全相同：`Color.enchronSurface`。

## 为何有效
Xcode 15 引入了 Generated Asset Symbols（`GeneratedAssetSymbols.swift`），自动为 Asset Catalog 中的每个资源生成 type-safe Swift 访问器。当手动定义同名属性时，编译器看到两个相同签名的声明，报 "invalid redeclaration"。

关键区别：
- **SPM build** 不处理 xcassets，因此不生成这些符号，手动 extension 不会冲突
- **Xcode build** 处理 xcassets 并生成符号，手动 extension 必然冲突
- 这意味��� SPM 测试可以通过，但 Xcode build 会失败 — 造成假阳性的测试信心

## 预防措施
- 为 Asset Catalog 创建 Color Sets 时，不要编写同名的 `Color` extension
- 如需自定义名称（如加前缀），在 Asset Catalog 中直接命名（如 `enchronSurface`），而非在代码中添加包装
- 如确实需要代码层的封装逻辑（如计算颜色、条件颜色），使用与 Asset Catalog 不同的属性名

## 相关问题
- docs/solutions/best-practices/visionos-swiftui-migration-pitfalls-2026-04-05.md — visionOS SwiftUI 迁移陷阱集
