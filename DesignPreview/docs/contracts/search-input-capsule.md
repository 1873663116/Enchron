# 组件契约:`SearchInputCapsule`(搜索输入胶囊)

> 状态:已定稿(契约层)。未实现。

## 0. 角色
胶囊形玻璃搜索输入框,带聚焦态与按压反馈。

## 1. 构造
`TextField` + `@FocusState` + 玻璃胶囊 + 搜索图标 + 按压反馈。`text` 双向绑定。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `text`(Binding) | 输入内容 | 框内文字 | live 传绑定 |
| `placeholder` | 占位提示 | 空时的灰字;默认「Search」 | 可变 |

## 4. 无障碍(硬要求)
- `accessibilityIdentifier`(默认 `...input-search`,可覆盖)。

## 5. 锁死
`width`(锁,默认 `Card.gridMin`,尺寸归容器管)、玻璃、胶囊、搜索图标、聚焦/按压、字体、所有相关 token——全锁。

## 6. 决策记录
1. **`width` 锁死**:不暴露。工具栏里搜索框宽度由容器决定,与 GridCard「尺寸归容器管」一致。
