# 组件契约:`SettingListGroup`(设置列表组)

> 状态:已定稿(契约层)。未实现。
> 与 `FileListGroup` 共享内部件 `ListGroupRowShell`,但**不同角色,不合并**。8 种 accessory 全是产品在用,无 surplus。

## 0. 角色
富设置列表:一组圆角分隔的设置行,每行标题+图标+可选支持文字,尾部挂一个「随类型而变」的控件,部分行可展开。

## 1. 构造
`SettingListGroup(items: [Item])` 声明式数组。行建在共享 `ListGroupRowShell`(圆角首尾、分隔线、悬停)上。

**`Item` 字段:** `title`、`systemName`、`supportingText`、`detail`(展开描述)、`keyValueDetail`(展开键值)、`expansion`(展开锚点)、`accessory`(尾部控件)、`embeddedControl`、`action`。

**`Accessory`(尾部槽 8 种,全部在用):** `none` / `automatic` / `menu` / `action` / `toggle` / `boundToggle` / `value` / `valueAction`。
**`EmbeddedControl`:** `cardSelection`(卡片选择网格)/ `centerSlider`(复用 `CenterSlider`)。

## 2. 变体
`Accessory` 枚举本身就是变体机制——同一行结构的尾部槽的 8 种填法。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `items`(`[Item]`) | 设置行声明数组 | 列出哪些设置、每行长什么样、尾部挂什么控件 | live SettingsPage + 橱窗都传 |

## 4. 无障碍(硬要求)
- 每行可定位;尾部控件(开关/菜单/值)暴露各自语义与当前值;可展开行的展开态可读。

## 5. 锁死
`ListGroupRowShell` 行壳、展开动画、所有相关 token——全锁。

## 6. 决策记录
1. **定为「一套组件」,不拆成 N 个组件**(已拍)。8 种 accessory 是同一行尾部槽的 8 种填法,行骨架/布局/展开/壳全共享;拆成 8 个组件会把整套行脚手架复制 8 遍。
2. accessory 的承载形态(一个枚举 vs 一个尾部**插槽** + 8 个小视图)是**实现期细节**;倾向插槽(每种 accessory 一个小可组合视图,而非一个胖枚举)。8 种全用,无 surplus。
