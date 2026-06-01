# 组件契约:`CenterSlider`(中心原点档位滑块)

> 状态:已定稿(契约层)。未实现。
> 内含内部子件 `GlassSliderRail`(纯视觉轨道,不对外)。被 `PlayerControlDeck`(时间轴缩放)和 `SettingListGroup`(embeddedControl.centerSlider)内部复用。

## 0. 角色
以中心为原点、带档位吸附的滑块,两端各一个图标,拖动取整数值。

## 1. 构造
拖拽手势 + 档位吸附逻辑;视觉轨道由内部子件 `GlassSliderRail` 渲染(点亮的中心带、玻璃旋钮)。`value` 双向绑定。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `value`(Binding) | 当前整数值 | 旋钮位置 | 宿主传绑定 |
| `range` | 取值范围 | 档位数;默认 `-5...5` | 可变 |
| `leadingSystemImage` / `trailingSystemImage` | 两端图标 | 左右端图标语义 | 可变 |
| `trackWidth` | 轨道长度 | 滑块多长 | **宿主不同**:时间轴宽、设置内窄 |

## 4. 无障碍(硬要求)
- `accessibilityLabel`(默认「Center slider」)+ `accessibilityIdentifier`(默认 `...CenterSlider`,可覆盖)。作为可调值控件,当前值需向辅助技术暴露。

## 5. 锁死
`trackHeight`(30,轨道厚度)、`knobSize`(26)、`dotSize`、图标列宽、`GlassSliderRail` 视觉、档位/拖拽逻辑——全锁。

## 6. 决策记录
1. **只暴露 `trackWidth`、锁 `trackHeight`**:滑块高度是轨道厚度(设计常量,非布局维度),所以「宽高成对」规则不适用——只长度随宿主变。
2. `GlassSliderRail` 是内部子件,不对外。
