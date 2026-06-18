# 组件契约:`GridCard`(文件网格卡)

> 状态:已定稿(契约层)。尚未实现——本文件只描述「最终怎么构造 + 暴露什么参数 + 各影响什么」,不含实现代码。
> 取代:`VideoCardLarge` + `FolderCard`(两者合并为本件)。

## 0. 角色
文件浏览网格里的一张卡:上方一块玻璃缩略图 + 下方一行标题,悬停时浮出补充信息。视频与文件夹是同一张卡的不同变体。

## 1. 最终怎么构造
一个标准件 `GridCard`(承载共享骨架:缩略图块、玻璃、卡片圆角、悬停高亮、标题排版、按压反馈)+ 两个变体静态工厂 `GridCard.video(...)` / `GridCard.folder(...)`。组装时只调工厂、填数据,不写卡片代码。

命名约定:本件 `GridCard`;环境卡平行命名 `EnvironmentCard`(已落实)。

## 2. 变体
| 变体 | 工厂 | 缩略图 | 悬停信息 |
|---|---|---|---|
| 视频卡 | `GridCard.video` | 现在:`film` 图标;将来:海报/视频帧(从随附文件提取) | 右上角标 + 左下大小 + 右下时长 |
| 文件夹卡 | `GridCard.folder` | `folder.fill` 图标 | 左下「N items」 |

缩略图内容是**骨架的内部能力**(图标挡 / 图片挡),由变体工厂各自钉死,**不开放给调用点选**——保证变体完整性(不能给视频卡配文件夹图标)。当前两个变体都用图标挡;海报到位时 `video` 内部切到图片挡。

## 3. 暴露参数(组装时仅能调这些)
**`GridCard.video`:** `title`(标题行)、`fileSize`(悬停左下)、`duration`(悬停右下)、`badges`(悬停右上玻璃角标,空=不显示)
**`GridCard.folder`:** `title`(标题行)、`count`(悬停「N items」)
**两变体共享:** `accessibilityIdentifier`(可选,稳定测试 id;不传则按变体+title 自动派生)

**不暴露:** 宽 / 高(尺寸由网格 resize 重排管,卡片现状不动)、缩略图输入、缩略图模式开关。

## 3.5 无障碍(硬要求,每件必备)
- 卡片是**可点网格项**,必须带稳定 `accessibilityIdentifier` 供端到端测试定位具体某张卡。
- `accessibilityLabel` 由 title + 变体类别(video/folder)派生,作为一个**合并的可点元素**朗读,而非把缩略图/角标/元数据拆成多个零散节点。

## 4. 锁死(组装不可改,token 驱动)
卡片圆角 `ShapeToken.card`、缩略图高度 `Card.thumbnailHeight`、缩略图填色 `Surface.elevated`、标题字体 `Typography.headline`、内边距 `Card.paddingH/V`、角标/元数据字体、悬停浮现动画 `AnimationToken.controlsTransition`、按压反馈 `.card`、玻璃效果、文件夹图标。元数据前景色**统一为 `.secondary`**(消除旧 `VideoCardLarge .secondary` / `FolderCard .primary` 的分叉)。

## 5. 决策记录
1. 合并 `VideoCardLarge`+`FolderCard` → `GridCard`:**采纳**(~90% 骨架重复,兄弟变体)。
2. `showsSupplementaryInfo` 参数:**删除**(全仓库无调用点改过)。
3. 元数据颜色:**统一 `.secondary`**。
4. 缩略图输入参数:**暂不暴露**,海报接入时再加 `poster:`。
5. 宽/高:**都不暴露**(只暴露宽不暴露高=体验差;尺寸归网格管)。现有网格布局不重写。
6. 无障碍:**补回**(初稿漏了)。暴露可选 `accessibilityIdentifier`,`accessibilityLabel` 由 title+变体派生。每份契约固定带「无障碍」段。

## 待办(实现阶段,非本契约)
- `ContentView` 的 `pressCardPreview`(原 1621 行)借用卡片的 `fileSize`/`duration` 字段塞任意文字来演示按压反馈——属组件库 hack,实现后应改为诚实的独立演示,不再借用 `GridCard` 字段。
