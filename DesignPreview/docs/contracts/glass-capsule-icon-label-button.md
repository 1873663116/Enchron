# 组件契约:`GlassCapsuleIconLabelButton`(玻璃胶囊图标文字按钮)

> 状态:已定稿(契约层)。未实现。
> 属**按钮家族**(与 `GlassCircleIconButton` 并列);目前仅组件库陈列,无 live 用法,按「按钮变体全留」决定保留。

## 0. 角色
胶囊形玻璃按钮,内含图标 + 文字,可点。圆形按钮放不下文字时用它。

## 1. 构造
`Button` 包一个 `Label(title, systemImage:)`,裁成 `Capsule()` + 玻璃 + 悬停 + 按压(`.control`)。与 `GlassCircleIconButton` 同源,差别是带文字、胶囊形。

## 2. 变体
按钮家族成员。可比照 `GlassCircleIconButton` 加具名预设工厂(若出现常用规格)。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `title` | 按钮文字 | 显示的文案 | 可变 |
| `systemName` | 图标 | 文字前的图标 | 可变 |
| `action` | 点按回调 | 点击行为;默认 `{}` | 可变 |

## 4. 无障碍(硬要求)
- `accessibilityLabel`:**必填**;`accessibilityIdentifier`:不传按 `title` 自动派生。

## 5. 锁死
`iconColor`(.white)、`minWidth`(默认 `Interactive.regular*2`;仅组件库为陈列覆盖过,无 live 需求 → 锁默认)、玻璃、胶囊、字体(`Typography.metadata`)、内边距、按压——全锁。

## 6. 决策记录
1. 保留(按钮家族变体全留)。
2. `minWidth` 锁默认(仅橱窗变过,无产品需求)。
3. 待 live 用法出现时,考虑加具名预设。
