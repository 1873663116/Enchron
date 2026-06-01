# 组件契约:`PlayerControlDeck`(播放控制台)

> 状态:已定稿(契约层)。未实现。
> 最复杂的一套组件,但**近乎零暴露参数**——定死后直接丢进视频页。

## 0. 角色
窗口播放的完整控制台:传输控制、进度、可展开的二级精度时间轴、播放/面板/更多控件。

## 1. 构造
自包含、定死的复合件。内含:播放按钮、传输按钮、进度条、可双击展开的精度时间轴(pixels-per-second 缩放,内部复用 `CenterSlider`/`GlassSliderRail`)、面板按钮、更多菜单、缩略提示。整套状态机内聚。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `timelineResetToken`(Int) | 改值即重置时间轴/进度 | 外部触发一次复位 | 仅 WindowPlaybackPage 传;其余调用点全用默认 |

**就这一个。** 没有可变控件——产品意图就是「拿来即用」。

## 4. 无障碍(硬要求)
- 内部已铺全套稳定 id:`...button-play`、`...button-<label>`、`...button-panel`、`...menu-more`、`...thumb` 等,可被端到端测试逐个定位。

## 5. 锁死
除 `timelineResetToken` 外**全锁**:进度/拖拽/精度时间轴/缩放/边界反馈/所有控件/所有 token。

## 6. 决策记录
1. 暴露面 = 仅 `timelineResetToken`,定死复合件(用户已确认意图)。
2. 内部复用 `CenterSlider`/`GlassSliderRail`(时间轴缩放)。
