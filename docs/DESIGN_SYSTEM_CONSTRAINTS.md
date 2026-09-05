# 设计系统的规则与平台约束

本文记录 `Modules/DesignSystem` 里那些**无法从代码本身读出**的事实：token 之间的结构关系、visionOS 与 SwiftUI 的实际行为、以及若干视觉数值的出处。单个 token 的取值不写在这里——它的真相源是 `Modules/DesignSystem/DesignTokens.swift`，读那一行比读转述准确。

## token 的三层结构

1. **primitives**：`Spacing`、`Radius`、`Stroke`——落在栅格上的裸值。
2. **semantics**：`Surface`、`AnimationToken`、`HoverStyle`、`Interactive`——意图。
3. **components**：`Card`、`Menu`、`ControlBar`——由前两层装配。

组件层只允许引用前两层，不允许在组件层重新引入裸值。产品侧的视觉数值必须来自 token 或 DesignSystem 组件，由 `Scripts/rules/verify_design_source_architecture.py` 的 `production-hardcoded-visual` 规则强制。

## 同心圆角

`Radius.panel(40) → card(32) → element(24)`，每一层等于外层减去 `Spacing.xs`（8）。这不是三个独立的数，而是一条关系：菜单容器用 `card`，它的 `Menu.glassPadding` 是 8，因此内部菜单项必须落在 `element` 上才与容器同心。非标准嵌套用 `Radius.concentric(outer:padding:)` 现算，不要另立常数。

`Radius.small`（12）不属于这条层级，它是标签与缩略图这类小圆角背景；徽章玻璃用 `Capsule()`。

**窗口圆角由系统管理**，任何情况下都不要手动设置窗口的 corner radius。

## 一个控件的四层形状必须同一

`ShapeToken` 存在的唯一理由是让下面四层落在同一几何上：

1. `clipShape` —— 视觉边界；
2. token 或系统材质 —— 视觉层级；
3. `contentShape(.hoverEffect, ...)` —— 注视高亮区；
4. `contentShape(.interaction, ...)` —— 命中区。

调用点各自手写 `RoundedRectangle(cornerRadius:)` 就会让四层漂开。之后若有包装层扩大命中范围，必须走 `enchronHoverContentShape(_:insets:)`：`insets` 是可见控件与扩大后目标之间的**静默边距**，hover 高亮不得画进去。

整张卡片要么是**一个真正的交互控件**（与列表行同一条路由契约），要么是纯展示（预览用）。不要在卡片外面再挂 `.onTapGesture`——它与卡片自身的手势争夺命中，实测不可靠。

第 3 层不能代替第 4 层：只给 hover 形状而不给 interaction 形状时，命中区在被 padding 撑开的整个 frame 上处于未定义状态，宿主报告 not hittable，唯一进得去的路径是绕开该控件的调试命令。

## 命中目标

`Interactive` 的视觉尺寸取自 Apple HIG，但**每个控件的有效目标必须达到 60pt**。28 与 36 自身达不到，靠周围留白补足；44 每侧至少 8pt 净空；60 与 64 自足。目前没有检查器强制这条，它只由本文与 `Scripts/rules/check_hover_region_clipping.py` 的 hover 裁切规则部分覆盖。

另两条同源的 HIG 取值：堆叠按钮之间最少 16pt；ornament 与窗口下缘的重叠量取 20pt。

## 可寻址性：标识符怎么取名

产品对控件的寻址靠 `.accessibilityIdentifier`，`Config/reachability_operation_inventory.json` 与 journey 都建立在它上面，所以取名不是自由的：

- 复合标识符的前缀必须能与宿主行区分开。设置项菜单用的不是 `Settings-menu-…`——某个设置自身的 id 里恰好含连字符时，那种形式与"该设置的宿主行"无法区分。
- 同一屏里标题重复的按钮必须各自带标识符。两行都把按钮叫 "Copy" 时，按 label 匹配是有歧义的，会落到树里靠前的那一个上。

## 玻璃边界

visionOS 的窗口根自带玻璃。可复用控件因此一律使用非玻璃层级（`View+EnchronGlass.swift` 的具名变体），调用点无法在窗口内部再造一层材质边界；只有窗口根、ornament 与空间附着物在各自宿主处经 `enchronGlassBackground(in:)` 显式选用平台玻璃。裸 `glassBackgroundEffect` 的所有权由 `verify_glass_usage.py` 钉死在 `View+Platform.swift`，包装器调用点是一张显式白名单。

原因不止是风格。`glassBackgroundEffect` 会把视图提升为**独立渲染层，任何祖先都无法裁切、遮罩或遮挡它**。网格卡片一旦带上它，滚动到边界时就画到窗口外并整张消失，而不是滑进侧栏下面。缩略图自带填充，玻璃从来只在占位符后面透出过。

浏览侧栏出于同一理由是**窗口自身表面的一部分，不是浮在窗口里的一块板**：浮板自带玻璃边缘，它的下缘停在窗口下缘之上，两者之间会露出一条页面。侧栏因此是方角、满高，只在尾缘画一道主题强调色的边界线标出内容区从哪里开始；前缘落在窗口自己的边界上，不需要边线。

## 注视 hover 的跨行协调

**visionOS 不向 app 代码暴露注视状态**。因此"某一行被注视时，它两侧的分隔线一起淡入"这类跨行效果，只能靠一个共享的 `@Namespace` hover group 实现：行激活自己的组，分隔线（以及尾随元数据）跟随该组，由系统在同一合成阶段、同一时序里一起完成。列表组的分隔线因此跟随它上下两行中的任意一行。

同一约束下，行高亮的圆角只圆外侧角（与容器裁切一致），内侧对着分隔线的一侧保持方角。

## 层级切换的过渡

浏览（Files 的文件夹层级、Emby 的目的地、Settings 的分类）三处都用同一对 token：`AnimationToken.levelTransition` 驱动、`TransitionToken.levelReplace` 定义进出。纯 `.opacity` 交叉淡入在新旧内容外观相同时不可见——两层全是文件夹图标的目录互切看起来像瞬移，只有缩略图变化的目录才"溶解"。`levelReplace` 是 `BlurReplaceTransition(.upUp)`：模糊加缩放对相同内容同样可见，切换的感知因此不再取决于内容差异。`Scripts/rules/verify_browser_surface_structure.py` 钉住三处调用与两个 token 的定义。

## 卡片 hover 揭示

`GridCard` 四种变体在注视下揭示的东西一致：观看进度条只在 hover 时出现（video、poster、episode 都经 `watchedProgressBar`，不直接画 `watchedEdgeProgressVisual`）；画在缩略图上的文字（video 的体积与时长行、episode 的标题与简介）背后是同一个 `thumbnailTextScrim`，它的高度是文字块高度乘 `1 + Card.textScrimLeadFactor`，随文字行数伸缩，不是缩略图的固定比例。folder 的缩略图是平面，不需要 scrim。同一个守卫脚本钉住这些结构。

## 系统 Menu 里哪种行留得住标识符

**系统 Menu 的内容随宿主 body 一起重建**：宿主窗口的 body 每重新求值一次，UIKit 就重建一次菜单并重新呈现已打开的子菜单。播放窗口的根 body 曾因 `.accessibilityValue` 快照读取每帧更新的播放位置而按播放时钟重算，三级菜单因此闪烁到无法点中；读取高频运行时属性的快照必须住在自己的 `ViewModifier`／子视图里（`WindowControlPlaneStateModifier`、`PlaybackAutomationStateProbe`），Observation 的失效范围就只有那一个节点。同理，菜单内容的 `onAppear` 不能改写被宿主 body 读取的状态：`setControlsFocused` 只在焦点值真正改变时登记一次交互。两条都由 `Scripts/rules/verify_playback_surface_structure.py` 钉住。

`.accessibilityIdentifier` 只保留在菜单当作一等 action 采纳的行上。`Picker` 行与 `Toggle` 行都是菜单自行布局的内容，二者到达 accessibility 树时**完全没有标识符**，任何东西都寻址不到它们，覆盖率检查也不会因此变红；`Button` 行保留标识符。三者在 2026-08-21 于设备上同一构建里实测。

代价是勾选标记的位置：`Picker` 把它画在尾缘，`MenuSelectionRow` 画在前缘，标题因此位移。这就是"这一行可被寻址"的全部价格。

## 系统拥有的表面

有几处表面故意不由 DesignSystem 造：

- **确认与错误对话框**走 visionOS 原生 `.alert`。呈现、居中、玻璃材质、背景压暗、默认焦点落在 Cancel，全部归系统；确认按钮的红色来自 `ButtonRole.destructive`，由 alert 容器在渲染时解析——**这里没有作者写下任何颜色，因此也不涉及颜色 token**。尺寸同样由系统决定，这些接口刻意不暴露尺寸参数。
- **侧栏玻璃**由系统 `NavigationSplitView` 提供，没有显式修饰符。
- **标签栏切换**由系统整棵替换视图树：新屏幕存在时旧屏幕已经消失，从这里根本够不到交叉淡入。因此入场只做淡入（仅透明度，窗口不缩放），这一条就足以消除切换时的硬切。

## 展开动效的锚点

展开/收起用的是**同一个 `Button`**，动作、accessibility 元素与命中目标全程稳定，只有内部符号随产品状态变化。这让状态归属留在 feature 调用点，也让 SwiftUI 能对符号做 content transition，而不是在两个独立控件之间来回替换。

一行的详情面板从哪里"长出来"取决于它在容器里的位置：靠上的行向下长（锚在自己的上缘），靠下的行向上长（锚在下缘），中间的行从中心放大。变化的只有 disclosure 的锚点与插入边——面板始终布局在行头之下。展开时行高变化与被它顶下去的那些行，用的是详情面板入场的同一条弹簧。

## SwiftUI 布局的三个坑

- **`ViewThatFits` 不给候选任何宽度**。一个"要多少给多少"的文本列会比卡片更宽并向两侧挂出去，首字符被卡片裁掉。文本列必须自己被量，不能靠推断。
- **两个维度都要在 `clipShape` 之前钉住**。只约束高度时，aspect-fill 的剧照会长过卡片宽度并溢到邻居上——外层的宽度 frame 会把超尺寸的缩略图**居中**而不是裁掉。
- **caption 要锚定在卡片自己的盒子上**（bottom-leading）。任其围绕文本自适应，它会比卡片宽并居中覆盖，首字符被推过前缘进入裁切区。

## 滑块族的共享与手势

`CenterSlider`（中心原点、有档位）、`RangeSlider`（前缘原点、连续）、`DetentedRangeSlider`（前缘原点、定步长）与时间轴缩放滑块共享 `GlassSliderRail` 的视觉：胶囊轨道、强调色亮条、白色旋钮。旋钮行程一律 `travel = trackWidth - knobSize`；亮条几何与拖拽手势由调用方计算与挂载，这样四者渲染一致。

三条来自实际缺陷的约束：

- **手势挂在静止的轨道上，绝不挂在移动的旋钮上**。挂在旋钮上时拖拽坐标系随旋钮移动，位移会自反馈，早期的抖动就来自这里。
- **轨道与档位点共处一列**，让点获得真实的布局空间。曾用裸 `.offset` 把点推到边界外，它们根本不合成；`.trackCenter` 对齐导引负责让两端图标对齐**轨道**中心而不是整列中点。
- **落到两端档位时不要弹跳**。中途吸附保留 `selection` 弹簧的磁吸手感，端点吸附必须无过冲，否则旋钮会被弹出被裁切的胶囊边缘再弹回来。

拖动状态要上抛给宿主行：拖动时注视 hover 会离开该行，只靠 hover 会让标题与数值 readout 消失。

## 艺术图的解码缓存

`URLCache` 已经在磁盘上保留压缩字节，每次重新出现时重复的是**解码**，而解码结果只能留在内存里，所以按 URL 键缓存解码后的位图。Emby 把图片的内容标签放进 URL，因此换了封面就是另一个键。`NSCache` 自身线程安全，共享实例不需要额外隔离。

预热按屏预取：解码缓存有界，预热预算再大也只会驱逐它刚装进去的东西；并发度取到"能喂饱网络又不与屏上帧竞争"为止。

## 视觉数值的出处

- **主题强调色**是应用图标背景的粉色 `#F4E0E8`——图标纵向渐变的中点。产品的信号色与启动器磁贴因此是同一个色相。
- **chrome 描边**用四分之一强度的强调色：一窗口的边如果都用满强度，会读成一格格亮框。
- **圆形不定式（advance）动画常数**取自 material-components-android 的 `CircularIndeterminateAdvanceAnimatorDelegate`，放在 token 里是为了与 Design Preview 共享同一套时序，而不是在视图里重新编码一遍周期。
- **字体一律走 `Typography` 语义映射，不用 `.system(size:)`**：系统 Text Style 自动处理 Dynamic Type 与 visionOS 的观看距离。
- **scrubber 的抓取区**比拇指宽得多。拇指按轨道高度绘制以便读作轨道的一部分，那远小于佩戴者能命中的注视目标，因此启动 scrub 并显示注视高亮的区域另有宽度（`thumbGrabWidth`）；"算点击而不算拖拽"的位移上限（tap slop）与它是两个概念，取得很小，任何有意的拖拽都会超过它。
- **详情页背景图向服务器请求的像素数**是限定值：原图是整幅制作剧照，解码它正是进入页面时卡住的原因。
- **按压反馈按面积分级**：大面积表面动得最轻，卡片才在空间里保持稳定；行的位移更小，否则密集列表读起来发跳；控件胶囊因为彼此隔离可以响应得更明显；单个图标用最强的缩放线索，与空间胶囊控件一致。

## 未决：滑块轨道尺寸尚未 token 化

`CenterSlider` 与 `RangeSlider` 的旋钮（26）与轨道高度（30）沿用既有 toggle 的尺寸以便复用，尚未提升为共享 token——提升与否需要人来定。这些字面量目前记在 `Config/` 下 design-source 检查器的基线里，不是无人看管的漏网之鱼。
