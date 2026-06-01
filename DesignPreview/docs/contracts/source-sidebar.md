# 组件契约:`SourceSidebar`(交互源列表侧栏)

> 状态:已定稿(契约层)。未实现。
> 关系:与 `CategorySidebar` 是**两个不同角色**,不是一个组件的两态。

## 0. 角色
Files 的来源侧栏:本地/SMB/WebDAV/文件夹,支持重排、滑动删除、多选、加来源,底部显示存储空间。全产品只有一个真实用法(主窗口 Files tab)。

## 1. 构造
自包含的交互标准件。**自己拥有**整套交互状态机(拖拽重排、滑删、多选、入场动画)。内部用 `EditableSourceSidebarRow`(交互行)+ `SourceSidebarRow`(纯视觉行),调用方都碰不到。底部存储条**内置**(DesignPreview 是假 UX,内部写死 mock 存储数字,不开参数)。

## 2. 变体
无。原 `capabilities` OptionSet **整个删除**——它当初只为让一个组件在「全功能/纯展示」间切;一旦拆成两个组件,理由蒸发。本件永远全功能。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `items`(Binding) | 来源数据列表 | 显示哪些来源;双向以承接重排/删除 | 每处都传 |
| `title`(可选) | 侧栏标题 | 顶部分区标题;默认「Sources」 | 默认 |

**每项数据契约 `SidebarSourceItem`:** `id / icon / title / isSelected / isEnabled / isOnline / isDeletable`。

## 4. 无障碍(硬要求)
- `containerIdentifier`:整个侧栏容器 id。
- `identifierPrefix`:子行 id 的前缀。
- **两者职责不同(容器 vs 行前缀),都保留**——live 调用里它俩是不同值,不可塌缩。

## 5. 锁死
全部交互逻辑(重排/滑删/多选/加源,**写死全开**)、存储条(内置 mock)、宽/高(token,Files 主侧栏定宽)、`showsStatusIndicators`(锁 true)、所有 `DesignTokens.SourceSidebar.*`、两个内部行件——全锁。

## 6. 决策记录
1. `capabilities` OptionSet:**删除**(拆分后失去存在理由)。
2. footer 泛型 `<Footer>`:**删除**,存储条改为内置(mock 数据)。
3. 两个 a11y id:**都保留**(职责不同;修正了早前「可塌缩」的误判)。
4. 1200 行实现:**单列内部评审**,以当前效果为黄金基准,本轮不碰。
