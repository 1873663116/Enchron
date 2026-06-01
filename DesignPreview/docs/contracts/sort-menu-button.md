# 组件契约:`SortMenuButton`(排序菜单按钮)

> 状态:已定稿(契约层)。未实现。

## 0. 角色
一个图标触发的原生菜单,用于选择排序字段与升降序。

## 1. 构造
SwiftUI 原生 `Menu`,label **复用 `GlassCircleIconLabel`**(图标 `arrow.up.arrow.down`)。菜单内容:Sort By(Name / Date Modified / Size)+ Order(Ascending / Descending),当前项打勾。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `sortKey`(Binding) | 当前排序字段 | 哪项打勾 + 排序结果 | live 传 `$sortKey` |
| `sortOrder`(Binding) | 升/降序 | 哪项打勾 + 排序方向 | live 传 `$sortOrder` |

## 4. 无障碍(硬要求)
- `accessibilityLabel` = "Sort";`accessibilityIdentifier`(默认 `...menu-sort`,可覆盖)。

## 5. 锁死
`iconColor`(.secondary,排序图标有意比白色暗;调用点零覆盖)、菜单结构与选项(排序字段/方向是固定集)、label 图标——全锁。

## 6. 决策记录
1. `iconColor` 锁 `.secondary`(与按钮家族的白色不同,有意为之)。
2. 菜单选项硬编码(排序维度固定),不开放。
3. 复用 `GlassCircleIconLabel` 作 label,不重画。
