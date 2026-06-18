# DesignPreview — 组件语言 / Component Language

DesignPreview 的设计系统词汇表。定义标准件、变体、组件库等核心概念,统一人与 Agent 的交流和文件命名。这是术语表,不是规范,也不是实现说明。

## Language

**标准件 / Standard Component**:
独占一个视觉角色的单一带参 SwiftUI 视图(如一个 `Card` 表达「卡片」这一角色)。同一角色不拆成多个 struct,差异一律走参数。
_Avoid_: 组件(过泛)、control、widget

**变体 / Variant**:
标准件的一种具名规范配置,代表可辨识的子类(如文件夹卡、视频卡都是 `Card` 的变体)。变体是参数配置,不是独立 struct。
_Avoid_: 变种、kind、style(除非确指某个参数名)

**组件库 / Component Library**:
陈列每个标准件及其变体实例、供人与 Agent 视觉审查和复用的表面。它是一等公民,不是待删的陈列馆债务。
_Avoid_: 陈列馆、showroom、catalog(口语可用,正式命名用 Component Library)

**竞争重复 / Competing Duplicate**:
两个以上的件服务**同一个 pattern**、纯粹冗余,只应保留一个。需人在 Canvas 上选出留存者,其余删除。
_Avoid_: 重复(过泛,需指明是竞争重复还是兄弟变体)

**兄弟变体 / Sibling Variant**:
两个以上的件服务**同一视觉角色但不同子类**(如文件夹卡与视频卡),应塌缩为一个标准件的多个变体,而非互删。
_Avoid_: 重复、变种

## 标准件名录 / Standard Component Roster

把视觉角色钉到代码里的真名。代码为唯一真相;新增条目前先 grep `struct X` 复核存在。

### 文件浏览

`GridCard`:
网格态的文件卡,一个 struct 两个变体——`.video`(视频卡)/`.folder`(文件夹卡)。
_Avoid_: VideoCardLarge、FolderCard、MovieCard、SceneCardMedium、裸 card

`FileListGroup`:
列表态的文件行分组,变体 `.video`/`.folder`(子行为 `FileListGroupRow`)。
_Avoid_: FileListRow、裸 list group

### 空间环境

`EnvironmentCard`:
沉浸观影环境的选择卡。领域概念 Environment 见根 `CONTEXT.md`(领域占词,组件用复合名,铁律见 `CONTEXT-MAP.md`)。
_Avoid_: SceneCardMedium、裸 card、把组件名当领域名

`EnvironmentCardCarousel`:
`EnvironmentCard` 的横向轮播容器。领域概念 Environment 见根 `CONTEXT.md`。
_Avoid_: SceneCarousel、裸 carousel

### 侧栏与导航

`SourceSidebarRow`:
Files 侧栏里的单条数据源行。
_Avoid_: 裸 sidebar、裸 source(领域 DataSource 见根 `CONTEXT.md`)

`CategorySidebar`:
Settings 的分类侧栏(条目模型 `CategorySidebarItem`)。
_Avoid_: 裸 sidebar、SettingsSidebar
注:顶层导航是系统 `TabView`,不是 sidebar。

### 播放

`PlayerControlDeck`:
播放控件甲板(播放/暂停、跳转等控件的承载条)。
_Avoid_: ControlBar、裸 deck

`PrecisionTimelineView`:
精度时间轴(可精细 scrub 的进度轴)。
_Avoid_: ScrubBar、裸 timeline

### 工具栏

`PathBreadcrumbMenu`:
路径面包屑菜单(当前层级路径 + 可点跳转)。
_Avoid_: MockBreadcrumb、裸 breadcrumb

`SearchInputCapsule`:
胶囊形搜索输入框。
_Avoid_: SearchBar、裸 search

`ViewModeCapsuleControl`:
网格/列表视图模式切换胶囊。
_Avoid_: ViewToggle

`NavBackForwardCapsuleControl`:
前进/后退导航胶囊(多分区胶囊参照实现)。
_Avoid_: BackForwardButton

`SortMenuButton`:
排序菜单按钮。
_Avoid_: 裸 sort

### 其它

`ConnectionFormPanel`:
SMB/WebDAV 等数据源的连接表单面板。
_Avoid_: 裸 form

`LoadingSpinner`:
加载转圈。当前唯一的加载态视觉;骨架屏(skeleton)是另一种加载视觉、当前未建。
_Avoid_: 把骨架屏与转圈混为一谈、裸 loading

`SettingListGroup`:
Settings 的设置行分组(子行 `SettingListGroupRow`)。
_Avoid_: 裸 list group

`GlassCircleIconButton` / `GlassCircleIconLabel`:
圆形玻璃图标按钮 / 其无交互的纯展示对应件。
_Avoid_: 裸 icon button

## 通用词禁裸用

下列通用词单独出现时指代不清,必须落到具体真名(对应的歧义也已写进各组件条 _Avoid_):

- **card** → `GridCard`(文件卡)/ `EnvironmentCard`(环境卡)
- **source** → `DataSource`(领域,见根 `CONTEXT.md`)/ `SourceSidebar*`(组件)
- **sidebar** → `SourceSidebarRow`(Files 数据源)/ `CategorySidebar`(Settings 分类);顶层导航是系统 `TabView`,不是 sidebar
- **list group** → `FileListGroup`(文件)/ `SettingListGroup`(设置)
- **library** → Component Library(组件库表面)/ Photos(系统相册数据源)
