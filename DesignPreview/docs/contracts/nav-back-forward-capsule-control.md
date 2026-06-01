# 组件契约:`NavBackForwardCapsuleControl`(前进/后退双区胶囊)

> 状态:已定稿(契约层)。未实现。
> 这是 DesignPreview 多分区胶囊的**参考实现**(见 `AGENTS.md` 多分区胶囊规则)。

## 0. 角色
一个胶囊,左半区=后退、右半区=前进,瞬时按钮(非选中态)。

## 1. 构造
胶囊内两个 chevron,`SpatialTapGesture` 按 `location.x < width/2` 判落点分区,每区独立按压反馈(`scaleEffect`,参数读 `DesignTokens.PressFeedback.icon`),`enchronGlassControl()` 提供玻璃。不用嵌套 Button(命中区互扰)。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `onBack` | 后退回调 | 点左半区行为;默认 `{}`=占位 | 可变 |
| `onForward` | 前进回调 | 点右半区行为;默认 `{}`=占位 | 可变 |
| `canGoBack` | 后退是否可用 | false → 左半区**灰显且不可点** | 文件夹导航语义 |
| `canGoForward` | 前进是否可用 | false → 右半区**灰显且不可点** | 文件夹导航语义 |

## 4. 无障碍(硬要求)
- 整体 `accessibilityElement(children: .ignore)` + `accessibilityIdentifier`(默认 `...navBackForward`,可覆盖)+ `accessibilityLabel` + hint「左半后退、右半前进」。
- 禁用半区需向辅助技术暴露**不可用状态**(disabled trait),且不响应点击。

## 5. 锁死
`iconColor`(启用态)、双区命中逻辑、玻璃、按压(`.icon`)、尺寸(`Interactive.regular/large`)、禁用态的灰色取值(走 token)——锁。
**不锁(动态态):** 每半区的灰显/可点由 `canGoBack`/`canGoForward` 驱动。原静态 `trailingOpacity`(前进恒暗化)被「禁用态灰显」吸收;是否保留为启用态的基础暗化,留实现期定。

## 6. 决策记录
1. **新增 `canGoBack`/`canGoForward`**:绑文件夹导航语义,禁用半区灰显且不可点(`iconColor`/尺寸等其余视觉常量仍锁)。
2. 与 `ViewModeCapsuleControl` **不合并**:一个是瞬时双按钮、一个是分段选中,交互语义不同。
3. 待办(内部):双区胶囊脚手架(手势+分区按压)与 ViewMode 重复,可抽共享内部件,留内部评审,不改暴露面。
