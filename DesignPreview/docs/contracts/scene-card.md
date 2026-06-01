# 组件契约:`SceneCard`(场景卡,原 `FeaturedSceneCard`)

> 状态:已定稿(契约层)。未实现。
> 主要由 `SceneCardCarousel` 组合(`live=0` 独立用法);命名与 `GridCard` 平行(此即之前预留的 `SceneCard`)。

## 0. 角色
单张沉浸场景卡:满幅背景图 + 场景信息(标题/编号/引语/模式/氛围)+ 顶部控件(返回/展开/更多)。

## 1. 构造
圆角卡,背景图 + 文字浮层 + 顶部控件(**复用 `GlassCircleIconButton`**)。通常由 `SceneCardCarousel` 排布;也可独立呈现单个场景。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `scene`(`FeaturedScene`) | 场景数据 | 图、标题、引语、模式、氛围 | 数据可变 |
| `onReturn` / `onExpand` / `onMore` | 三个动作回调 | 顶部三个控件行为 | 可变 |

**内部(非暴露):** `detailVisibility`、`atmosphericFade`(0–1 动画钩子)由 `SceneCardCarousel` 按滚动位置驱动,**不是调用方参数**。

## 4. 无障碍(硬要求)
- `accessibilityIdentifier` + `accessibilityLabel`(场景标题);顶部三控件各自有 label。

## 5. 锁死
卡片圆角、背景图处理、文字布局、顶部控件、所有相关 token——全锁。

## 6. 决策记录
1. **重命名 `FeaturedSceneCard` → `SceneCard`**(与 `GridCard` 平行,落实预留命名)。
2. `detailVisibility`/`atmosphericFade` 定为**轮播驱动的内部钩子**,不进暴露面。
