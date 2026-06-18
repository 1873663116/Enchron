# CONTEXT-MAP

本仓有两套术语表，分层裁决「某个词进哪一层」。立此结构与判据见 `docs/adr/0006`。

| 术语表 | 管什么 |
|---|---|
| 根 `CONTEXT.md` | **全局领域语言**——跨模块（PlaybackCore / PlayerUI / FileBrowsing / SpatialScene / Persistence）都要 reason about 的领域事实 |
| `DesignPreview/CONTEXT.md` | **组件语言**——DesignPreview 渲染出的视觉角色、屏幕、tab、面板分类的名字 |

## 分层判据（三问，逐词过）

1. 别的模块（非 View 层）需要 reason about 它吗？→ **是**：全局领域语言，进根 `CONTEXT.md`。
2. 否 → 它是某个**视觉角色 / 屏幕 / tab / 面板分类**的名字吗？→ **是**：组件语言，进 `DesignPreview/CONTEXT.md`。
3. 否 → 它只是**渲染出来的一串文字**（按钮文案 / 菜单项 / toast / picker 选项 / 占位符）？→ 两个表都不进；贴在用例表的 `accessibilityIdentifier` 锚点旁——锚点是稳定真相，文案可本地化。

## 铁律

同一个名字**绝不在两个表里都定义**。当一个 UI 组件是某领域概念的屏上投影（`EnvironmentCard` ↔ `Environment`），领域词占据这个词、归根表；设计层用**复合名**定义组件，并在 `_Avoid_` 交叉引用领域词。
