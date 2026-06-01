# 组件契约:`ViewModeCapsuleControl`(网格/列表双区切换胶囊)

> 状态:已定稿(契约层)。未实现。
> 与 `GridCard`(网格)/ `FileListGroup`(列表)联动:本控件切换文件浏览的两种布局。

## 0. 角色
一个胶囊,左半区=网格、右半区=列表,分段选中态(持久,带选中指示)。

## 1. 构造
与 NavBackForward 同款双区胶囊脚手架(`SpatialTapGesture` 分区 + 按压反馈 + `enchronGlassControl`),额外用 `matchedGeometryEffect` 做选中圆点滑动指示。`selection` 双向绑定。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `selection`(Binding) | 当前视图模式(0=网格 / 1=列表) | 高亮哪半区 + 联动页面布局 | live 传 `$viewMode` |

## 4. 无障碍(硬要求)
- 整体 `accessibilityElement(children: .ignore)` + `accessibilityIdentifier`(默认 `...viewMode`,可覆盖)+ `accessibilityLabel` + hint「左半网格、右半列表」。

## 5. 锁死
`iconColor`(.white)、`unselectedOpacity`(0.45)、图标(`square.grid.2x2` / `list.bullet`)、选中指示、双区命中逻辑、玻璃、按压、尺寸——全锁(调用点零覆盖,live 显式传的 `iconColor:.white` 即默认值,锁后该参数从调用点消失)。

## 6. 决策记录
1. 视觉常量全锁。
2. 与 NavBackForward **不合并**(分段选中 vs 瞬时按钮)。
3. 建议(非阻塞):`selection` 由 `Int` 改 `enum {grid, list}` 提升类型安全,实现阶段定。
