# 组装参考:`PlayerSettingsPanel`(播放设置面板)

> 状态:**不是一个组件**,是现有标准件的一份**拼装参考**。
> 因此没有「暴露参数」一说,也没有待确认项。当前以 `PlayerSettingsPanelPreview` 形态在 `ContentView`。

## 是什么
播放设置面板 = **分类侧栏 + 设置列表 + 统一玻璃**的组合,全部用现成标准件拼:

- 左:`CategorySidebar`(静态大类分类器)——选设置大类。
- 右:`SettingListGroup`(对应大类的设置项)。
- 外:统一一层 `enchronGlass*` 把二者罩成一个面板。

## 怎么用
组装时**直接抄这份参考**(`PlayerSettingsPanelPreview`)。若不合适,在组装处调宽度、长度、内部 padding 即可——这些是页面级布局,本就允许在组装层调。

不重画任何 sidebar / setting list;它们的参数面各看各自契约(`category-sidebar.md`、`setting-list-group.md`)。

## 备注
- 这份参考证明了「复合面板无需新组件,纯复用 + 玻璃层」即可成立。
- 不在「标准件双射」计数内(它不是标准件,是组装样板)。
