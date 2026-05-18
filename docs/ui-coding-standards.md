# UI Coding Standards

涉及 UI 改动时必读。本文件是 AGENTS.md 中"UI 编码约束"的详细规范。

---

## Design Token 强制引用

Token 定义：`XrPlayer/Shared/DesignSystem/DesignTokens.swift`
Glass 封装：`XrPlayer/Shared/DesignSystem/View+EnchronGlass.swift`
语义色：Asset Catalog（`Color.enchronPrimary` 等 9 色）

| 分类 | 规则 |
|------|------|
| Radius | 引用 `DesignTokens.Radius.*`，禁止硬编码 |
| Typography | 引用 `DesignTokens.Typography.*` / `SymbolSize.*` |
| Spacing | 引用 `DesignTokens.Spacing.*`，禁止硬编码 padding 数字 |
| Animation | 引用 `DesignTokens.Animation.*`，禁止内联动画参数 |
| Color | 使用语义色或 Asset Catalog 色；禁止 `Color(red:green:blue:)` 和裸 `.white/.black` |
| Material | 使用 `enchronGlass*()` 封装；直接调 `.glassBackgroundEffect()` 需注释说明原因 |

### Token 未覆盖时

- **有人值守**：上报询问，由人类决定扩展 Token 还是允许例外
- **无人值守（overnight）**：可复用已有 Token；需新增 Token 分类 → 标记 BLOCKED，等人确认

---

## 形状一致性（Shape Consistency）

一个可交互组件有四层形状（clipShape、glass、hover、hit-test），必须完全一致。
**禁止手动组合这四层** — 必须通过 `enchronGlass*()` 封装一次搞定。

| 禁止 | 替代 |
|------|------|
| 手动写 `.clipShape()` + `.contentShape()` + `.hoverEffect()` 组合 | 用 `enchronGlass*()` 封装 |
| 手动构造 `RoundedRectangle(cornerRadius: N)` | 用 `DesignTokens.ShapeToken.*` |
| 裸写 `.shadow()` | 删除，信任系统空间光照 |
| 裸写 `LinearGradient(.black)` 做暗角 scrim | 用 ornament 架构 + 玻璃材质保证对比度 |
| 裸写 `.glassBackgroundEffect()` | 用 `enchronGlass*()` 封装 |

### 封装对照表

| 封装方法 | 形状 | Hover | 用途 |
|---------|------|-------|------|
| `enchronGlassWindow()` | base (40pt) | 无 | 窗口主面板 |
| `enchronGlassControl()` | capsule | 无 | 控制栏 ornament |
| `enchronGlassPanel()` | card (20pt) | 无 | 内容面板、弹窗 |
| `enchronGlassCard()` | card (20pt) | `.lift` | 视频/文件夹卡片 |
| `enchronGlassMenuItem()` | card (20pt) | `.highlight` | 菜单行、列表项 |
| `enchronGlassMenu()` | card (20pt) | 无 | 菜单容器 |
| `enchronGlassBadge()` | badge (10pt) | 无 | 标签、徽章 |
| `enchronGlassPill()` | capsule | `.lift` | 筛选胶囊按钮 |
| `enchronGlassSidebar()` | 系统管理 | 系统管理 | 侧边栏 |

### 需要新封装时

- **有人值守**：上报讨论，在 `View+EnchronGlass.swift` 中新增封装
- **无人值守**：标记 BLOCKED，不得自行裸写形状组合

---

## hoverEffect 语义规则

- 卡片 / 独立按钮 → `.hoverEffect(.lift)`
- 菜单 / 面板内列表项 → `.hoverEffect(.highlight)`
- 所有可交互组件必须挂 `.hoverEffect()`，不得遗漏

---

## Accessibility

### 硬性（必须）

所有 `Button` 和可交互 `View` 必须包含：
- `accessibilityIdentifier("模块-组件-类型-名称")` — E2E 测试锚点
- `accessibilityLabel(...)` — VoiceOver 朗读文本

命名规范：`{BoundedContext}-{Component}-{type}-{name}`
示例：`"PlayerUI-Controls-button-playPause"`

### 推荐

- `accessibilityHint(...)` — 描述操作结果
- `accessibilityTraits(...)` — 如 `.isSelected`、`.isButton`
