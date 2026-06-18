# 组件契约:`EnvironmentCardCarousel`(环境卡轮播)

> 状态:已定稿(契约层)。未实现。
> live:CampEnvironmentPage(SenseZone Volume 内容)。内部由一排 `EnvironmentCard`(原 `FeaturedEnvironment`)组成。

## 0. 角色
SenseZone Volume 里的环境卡轮播:横向滚动/拖拽/视差的一排沉浸环境卡。

## 1. 构造
横向滚动 + 拖拽手势 + 视差/沉降动画,内部渲染一排 `EnvironmentCard`,自己管理滚动位置、沉降、细节浮现时机。整套交互内聚在组件里。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `environments`(`[FeaturedEnvironment]`) | 环境数据列表 | 轮播里有哪些环境;默认 `FeaturedEnvironment.fixtures` | 可变 |
| `onReturn` | 返回回调 | 卡片左上返回按钮行为 | CampEnvironmentPage 传 |

**每项数据契约 `FeaturedEnvironment`:** `id / imageName / title / environmentNumber / quote / mode / atmosphere`。

## 4. 无障碍(硬要求)
- `accessibilityIdentifier`(默认 `...EnvironmentCardCarousel`);各环境卡及其控件可定位。

## 5. 锁死
全部滚动/拖拽/视差/沉降逻辑、卡片排布、所有相关 token——全锁。`EnvironmentCard` 的动画态由本轮播驱动,不外泄。

## 6. 决策记录
1. 对外面就 `environments` + `onReturn`,其余全内聚(与 `SourceSidebar` 同样的「复杂内聚、暴露面小」)。
2. `FeaturedEnvironment` 模型字段 `mode`/`atmosphere` 现为 String,实现期可考虑改 enum(非阻塞)。
