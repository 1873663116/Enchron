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
