# 组件契约:`FileListGroup`(文件列表组)

> 状态:已定稿(契约层)。未实现。
> 关系:与 `SettingListGroup` 共享内部件 `ListGroupRowShell`,但**是不同角色,不合并**。
> 是 `GridCard` 的「列表视图」对应物——同一批文件内容(视频/文件夹)的另一种布局,由 `ViewModeCapsuleControl` 切换。

## 0. 角色
文件浏览的列表视图:一组圆角分隔的行,每行一个文件/文件夹(图标 + 标题 + 元数据,可点)。

## 1. 构造
一个分组列表标准件。行 `FileListGroupRow` 建在共享的 `ListGroupRowShell`(圆角首尾、分隔线、悬停)之上。`Kind`(video/folder)决定行图标(film/folder)。

## 2. 变体
组件层无变体。行的 video/folder 是**每项数据**(`Item.kind`),不是组件变体。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `items` | 文件行列表 | 列出哪些文件/文件夹 | HomeFirstLaunch / ContentView 都传 |

**每项数据契约 `FileListGroup.Item`:** `kind`(video/folder)、`title`、`metadata`、`action`。

## 4. 无障碍(硬要求)
- `accessibilityIdentifier`:组容器 id(默认 `DesignPreview-FileListGroup`,可覆盖)。
- 每行可被端到端测试定位(行 id 由组前缀 + 项派生)。

## 5. 锁死
`ListGroupRowShell` 行壳、行图标(film/folder)、圆角(`Radius.element`)、悬停、所有相关 token——全锁。

## 6. 决策记录
1. 不与 `SettingListGroup` 合并(共享 `ListGroupRowShell` 即可,角色不同)。
2. 跨件一致性备注:与 `GridCard` 的 `.video`/`.folder` 表达的是**同一个文件类别概念**(两种布局)。「文件类别」的表达将来宜对齐(GridCard 用工厂、FileListGroup 用 `Kind` 枚举,目前略不一致),非阻塞。
