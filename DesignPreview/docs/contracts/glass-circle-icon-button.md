# 组件契约:`GlassCircleIconButton`(玻璃圆形图标按钮)

> 状态:已定稿(契约层)。未实现。

## 0. 角色
圆形玻璃图标按钮,点按触发动作。播放窗口关闭/放大、环境卡返回/展开等都是它。

## 1. 构造
分层一对:`GlassCircleIconLabel`(纯视觉:玻璃圆 + 图标 + 悬停 + 按压,**不可点**)+ `GlassCircleIconButton`(把 Label 套进 `Button(action:)`,**可点**)。Button 复用 Label,不重画。**保留分层**(Label 要作为子件被 `SortMenuButton` 等内部复用;visionOS 上装饰图标不该带 Button 的焦点/按压语义)。

## 2. 变体
**具名图标预设工厂**:`GlassCircleIconButton.close(action:)` / `.expand(...)` / `.back(...)` 等常用按钮。`systemName` 仍开放,但**组装约定**:优先调具名预设;没有预设才传裸 `systemName`,且要顺手补一个预设。目的是把「现造图标」从随手行为,变成需显式新增预设的动作。整个按钮家族保留,不删。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `systemName`(或经预设) | SF Symbol | 显示哪个图标 | 每处都变 |
| `action` | 点按回调 | 点击行为;默认 `{}` = 占位 | live 有的传有的不传 |

## 4. 无障碍(硬要求)
- `accessibilityLabel`:**必填**(icon-only 控件,旁白朗读用)。
- `accessibilityIdentifier`:稳定测试 id;不传则按 `systemName` 自动派生。

## 5. 锁死
`iconColor`(锁,按钮调用点从不改,永远默认白)、玻璃、圆形、悬停 `.automatic`、按压 `.icon`、视觉/命中尺寸(`Interactive.regular/large`)、字体(`SymbolSize.control`)——全锁,全 token。

## 6. 决策记录
1. Label/Button:**保留分层**,不合并。
2. `iconColor`:**锁死**(从暴露面移除)。
3. 图标:加**具名预设工厂**,`systemName` 仍开但约定优先用预设。
4. 按钮家族:**全留**,不删变体。
