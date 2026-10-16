# 设计系统的规则与平台约束

本文记录 `Modules/DesignSystem` 里那些**无法从代码本身读出**的事实：token 之间的结构关系、visionOS 与 SwiftUI 的实际行为、以及若干视觉数值的出处。单个 token 的取值不写在这里——它的真相源是 `Modules/DesignSystem/DesignTokens.swift`，读那一行比读转述准确。

## token 的三层结构

1. **primitives**：`Spacing`、`Radius`、`Stroke`——落在栅格上的裸值。
2. **semantics**：`Surface`、`AnimationToken`、`HoverStyle`、`Interactive`——意图。
3. **components**：`Card`、`Menu`、`ControlBar`——由前两层装配。

组件层引用 primitives 与 semantics。视觉尺寸、颜色和动效由 token 管理。`verify_design_source_architecture.py` 同时扫描产品调用点和 DesignSystem 组件内部的裸视觉值；乘除中的无量纲系数属于几何计算。圆角形状的定义归 `ShapeToken` 和获准的共享形状实现，产品调用点不能用 radius 与 spacing token 临时拼装形状。构建和 CI 复用同一检查器；自测验证检查器能拒绝错误源码。

## 同心圆角

`Radius.panel → card → element` 通过外圆角减去内边距保持均匀内缩的嵌套关系。非标准嵌套使用 `Radius.concentric(outer:padding:)`。菜单行使用 `ShapeToken.menuRow` 的胶囊轮廓，可见背景在命中行中按 `Menu.rowVisualInset` 与 `Menu.rowVerticalInset` 分别内缩水平和垂直边距；`enchronHoverTarget(visual:interaction:insets:)` 统一扩大命中区，并以可见图形独立裁切 hover，静默边距只参与命中。菜单外框从 SwiftUI 的 `GeometryProxy.concentricCornerRadii` 读取容器相对圆角，使用最大值统一四角，并保留由行半高加内边距推导的最低圆角。菜单外框的材质、裁切和命中形状使用同一个解析结果。

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

visionOS 的窗口根自带玻璃。可复用控件因此一律使用非玻璃层级（`View+EnchronGlass.swift` 的具名变体），调用点无法在窗口内部再造一层材质边界；只有窗口根经 `enchronWindowGlassBackground(_:)`（`MainView`、`PlayerView`）、ornament 与空间附着物经 `enchronGlassBackground(in:)`（`FusedPlayerPanel`）在各自宿主处显式选用平台玻璃。裸 `glassBackgroundEffect` 的所有权由 `verify_glass_usage.py` 钉死在 `View+Platform.swift`，包装器调用点是一张显式白名单。

原因不止是风格。`glassBackgroundEffect` 会把视图提升为**独立渲染层，任何祖先都无法裁切、遮罩或遮挡它**。网格卡片一旦带上它，滚动到边界时就画到窗口外并整张消失，而不是滑进侧栏下面。缩略图自带填充，玻璃从来只在占位符后面透出过。同一条性质决定环境卡不能带玻璃：`TabView` 的页签栏是窗口自己的 ornament，层级低于任何独立渲染层，卡片一旦带玻璃就压在它上面。环境卡因此走 `enchronCardSurface(in:)` 的材质表面，与窗口内其它控件同在一条渲染路径上。

窗口平面同时是内容可见性的边界：窗口内容只有经 `offset(z:)` 落在平面之前才画得出来，落在平面及其之后的部分被窗口自己的材质挡掉。`EnvironmentCarousel` 的深度偏移因此在 `windowFrontClearance` 处封底，`centerDepthOffset` 与 `sideDepthOffset` 只决定卡片之间的前后差，不会把任何一张卡片推过这条边界。

窗口对自身的 SwiftUI 内容不做裁切：内容超出窗口矩形时照样画在空间里，不会被窗口收掉，`clipShape` 因此仍是内容不越界的唯一手段。同一条性质也决定了玻璃不能由手写形状提供：形状尺寸归零时平台按自己的边界绘制，圆角随之丢失，轮廓不再跟随窗口。

## 环境页的最小化

浏览窗口缩到紧凑胶囊时，轮廓由 `MainView` 自绘的 `CenteredRevealShape` 给出，不依赖窗口自身的形状。形状尺寸在展开尺寸与 `compactSize.height` 见方之间动画，圆角同时从 `Radius.card` 收到 `compactSize.height / 2`，因此中间帧始终是圆角、末端是完整半圆；`animatableData` 是尺寸与圆角的复合，`verify_playback_surface_structure.py` 钉住它不走 `shape.size()` 包装。这条路径要求形状尺寸永不归零，归零会退回平台边界绘制。

窗口的物理尺寸在整条过渡里保持不变：紧凑态是画在窗口内部的一个形状，窗口仍是展开尺寸。玻璃由 `glassBackgroundEffect(in:)` 按传入形状填充，轮廓因此逐帧跟随形状；形状行进期间底板保留自己的玻璃，落定后切 `.never` 让出可见表面，由胶囊控件自己的玻璃接替。

形状变形与两侧的淡入淡出分属三个动画作用域：形状由外层的 `environmentPlateMorph`（`environmentPlateMorphDuration`，1.0 s spring）承载，内容透明度由 `EnvironmentContentFade` 承载，胶囊控件由转场承载。把淡入淡出写在同一修饰符链上时，靠上的 `.animation(_:value:)` 会把形状动画一起改成自己的时长，底板因此走完得比预期快得多。

过渡是严格反向的：内容与控件在缩小时即刻离场（`environmentContentExit` 0.15 s、`environmentControlsExit` 0.45 s），在展开时于底板形状落定的尾段归位（`environmentContentEntrance`、`environmentControlsEntrance`，延迟为 `environmentPlateMorphDuration` 减去各自时长）。`.animation(_:value:)` 两个方向共用一个动画，做不到这件事，两个方向因此各有一个具名 token。

tab bar 的隐藏与形状变形同一刻发出、不加动画包装；它是 `TabView` 的系统页签栏（`toolbarVisibility(_:for: .tabBar)`），淡出曲线与时长由系统决定，app 只能决定何时隐藏。

`EnvironmentCard` 的缩略图按外观取浅色或深色图，切换以 `AnimationToken.controlsTransition` 溶解：图片以图片名为 `.id`、带 `.opacity` 转场，容器用 `.animation(_:value:)` 驱动，与 `LevelContent` 的层级替换同一手法。场景自身的浅深材质过渡是 1.2 秒，与这条 0.4 秒的溶解不同步，卡片会先落定。

浏览侧栏出于同一理由是**窗口自身表面的一部分，不是浮在窗口里的一块板**：浮板自带玻璃边缘，它的下缘停在窗口下缘之上，两者之间会露出一条页面。侧栏因此是方角、满高，只在尾缘画一道主题强调色的边界线标出内容区从哪里开始；前缘落在窗口自己的边界上，不需要边线。

## 环境页构图

轮播的整套几何按窗口宽度等比派生：基准宽 `EnvironmentCarousel.referenceWindowWidth` 是构图设计尺寸所对应的窗口宽度，取值等于浏览窗口的默认宽度；缩放因子是窗口内容宽度与基准宽的比，`MainView` 的 `expandedSize.width` 同时供给底板裁切与这条缩放，卡片与底板因此不会互相越界。`EnvironmentCard.metrics(scale:)` 与 `EnvironmentCarousel.metrics(scale:)` 是唯一的推导处，卡片尺寸与内边距、卡片间距、前后深度、边缘滑出距离、退场深度、顶部 scrim 高度与拖拽行程都在其中。浏览窗口的宽度在 `BrowserWindowLayout` 的区间内连续可变，重排逐帧跟随，卡片因此在任何窗口尺寸下都不被底板裁切；窗口内容宽度由 `BrowserWindowLayout.minimumSize` 兜底，缩放因子随之有下限，构图不会随窗口一起缩到失去可读性。

参与缩放的只有几何：字号走 `Typography` 语义映射，卡片上的按钮保持 HIG 目标尺寸，圆角固定为 `Radius.card`，卡片内的文字块与控件不随卡片等比放大。

`TabView` 的页签栏是窗口 ornament，不占窗口内容宽度，环境页的宽度因此就是窗口内容的宽度。

## 独立菜单

独立自制菜单由 `AnchoredMenuPresentation` 与 `AnchoredMenuLayer` 呈现。窗口设置与沉浸播放共用组件，菜单玻璃由 `AnchoredMenuSurface` 管理。列表宽度根据内容测量并受 `Menu.minimumWidth`、`maximumWidth` 和可用空间限制，高度根据内容测量并受统一上限限制。剧集网格用整列交互单元决定宽度，图标／列表切换保持宽度。编辑表单使用独立尺寸档位。

菜单展开的整条轨迹避开触发按钮，包括弹簧过冲。三级菜单保留二级菜单，沿可用的一侧展开，重叠只发生在边缘。出现和消失由同一个 `menuPopup` token 驱动位置、缩放和透明度。背景、二级菜单、三级菜单按 `Menu.layerDepth` 等距排列，空间附件不叠加额外前移。菜单状态控制输入独占和自动隐藏，不能改写 hover 状态。 两级菜单同时存在时，二级区域的点击只关闭三级并消耗该次点击；三级关闭动画结束前的点击不排队打开其他三级。点击两级菜单并集之外关闭两级，三级内部留白保持菜单打开。

菜单行、数字单元和分段胶囊内的各按钮通过 `enchronHoverTarget(visual:interaction:insets:)` 分开声明可见轮廓和命中轮廓。`EnchronHoverRegion` 在扩大后的目标中按静默边距生成可见路径。hover 检查器覆盖 Button、Menu 与 ButtonStyle，拒绝扩大 hover 标签的样式、多个直接子按钮共享父容器 hover，以及共享实现中混用可见与命中形状。Enchron 和 EnchronDebug 的设计源码构建阶段复用该检查；检查失败会终止 Build。CI 使用相同检查，单元测试验证路径和检查器的拒绝行为。真机注视高亮的合成结果仍需佩戴者验收。

visionOS 的菜单外部输入面使用 `Surface.menuDismissInput`，并禁用 hover。完全透明的 `Color.clear` 即使声明 interaction shape 和 Button，也不能可靠接收真机间接输入；输入面的微量不透明度用于建立命中区域。

## 注视 hover 的跨行协调

**visionOS 不向 app 代码暴露注视状态**。因此"某一行被注视时，它两侧的分隔线一起淡入"这类跨行效果，只能靠一个共享的 `@Namespace` hover group 实现：行激活自己的组，分隔线（以及尾随元数据）跟随该组，由系统在同一合成阶段、同一时序里一起完成。列表组的分隔线因此跟随它上下两行中的任意一行。设置列表的每一行都有行级 highlight，带按钮（菜单胶囊、动作胶囊、开关）的行也不例外：行不是 Button 时 `ListGroupRowShell` 仍给它 `.highlight`，尾随控件经 `enchronHoverActivation(in:)` 激活同一个行组，注视到控件时控件自己的 hover 叠在行高亮之上。

同一约束下，行高亮的圆角只圆外侧角（与容器裁切一致），内侧对着分隔线的一侧保持方角。

## 层级切换的过渡

浏览（Files 的文件夹层级、Emby 的目的地、Settings 的分类）三处都经 `.levelContent(id:)`（DesignSystem）：它内部是 ZStack + `.id` + `TransitionToken.levelReplace` + `AnimationToken.levelTransition`，页面不直接触碰这两个 token，守卫脚本禁止它们出现在页面源码里。

纯 `.opacity` 交叉淡入在新旧内容外观相同时不可见——两层全是文件夹图标的目录互切看起来像瞬移，只有缩略图变化的目录才"溶解"。两层因此不同时可见：`levelReplace` 的 removal 是 `levelExitDuration`（0.12 s）easeIn 淡出，insertion 是 `.identity`——新层以完整布局插入却保持透明，何时揭示由 `levelContent` 决定，一个转场自己没法等一份清单。交叉淡变（同时半透明）在内容相似时叠出残影，加位移能让切换可见但佩戴者不接受任何移动；不重叠之后，相似内容看到的是暗一下再亮回来的明确信号，差异大的内容仍是平滑过渡。2026-09-05 真机否决了模糊替换、对称位移、同向位移三版。

揭示的时刻取两个条件里先到的那个：层级经 `.levelReadiness(_:)` 上报内容已落定，或者已经空白了 `levelPlaceholderThreshold`（0.4 s）。前者是常态——本地目录与 Settings 分类在第 0 帧就落定，等待只剩旧层淡出的那 0.12 s，随后 `levelEnterDuration`（0.25 s）easeOut 淡入。后者是上界，它保证一份迟迟不回的远程清单不会把页面无限期留空；超时揭示的是该层级自己的占位。清单在等待途中到达时按已等时长扣减剩余等待（`LevelReveal.remaining`）而不重新计时。不上报 readiness 的层级视为已落定。第一个层级立即揭示：它前面没有可淡出的旧层，压住它只会让窗口在启动时空着。

`Scripts/rules/verify_browser_surface_structure.py` 钉住三处调用、两个 token 的定义、`levelContent` 的门控与两个浏览层级的 readiness 上报。

## 侧栏进出与卡片网格

Files 与 Emby 的侧栏都经 `SidebarSplitLayout`：内容区宽度随侧栏在 0.4 s 内连续变化，是真正的"推"。它能不掉帧，靠的是网格：卡片网格是 `CardGrid`（内部是自定义 `FlowGridLayout`：顺序排放、放不下换行；卡宽固定；`FlowGridLayout` 按当前宽度算出列数，把整行余量平均分进列间距（下限 16），列的 x 位置固定，不满的行沿用同一套列位置从左排起——Finder 图标视图的两端对齐。行因此填满、左右边距都等于页边距、上下列对齐；宽度连续变化时只有间距在变。固定间距加 leading 对齐把全部余量堆在右侧（最小与最大窗口下右边距曾达 84/204 pt）、整块居中让不满一行的卡片居中、列宽自适应让每帧每张卡重排版，三者都被否决（2026-09-07 真机）——卡宽固定（Files 224、Emby 180、间距 16）而窗口宽度连续可变；代价是列数变化那一帧整块横移最多半个卡位；加封面可视性门控环境；页面不直接使用 `FlowGridLayout`），每张卡片是身份稳定的子视图，宽度逐帧变化时只重算坐标；`LazyVGrid(.adaptive)` 在列数变化的那一帧会整行销毁重建卡片（图片、hover、材质全部重来），几十张卡就掉帧（2026-09-05 真机）。"宽度一步到位再让卡片滑到新位置"的折中被否决：卡片先跳后动。

非 lazy 网格的代价由可视性门控抵消：`AsyncArtworkImage` 在 `artworkLoadsWhenVisible` 环境下只在 `onScrollVisibilityChange` 报告可见后才加载，离开可视区释放已解码的引用（NSCache 仍持有）；两个网格都设了这个环境，网格之外的封面（详情页、播放面板）不受影响。这样同一时刻只有可视区的卡片在解码，与 lazy 网格同一量级。

## 加载与动画不同时发生

原则（取自 Apple TV 的详情页）：内容没准备好时宁可什么都不显示；准备好后先把布局做完，再播动画。布局和淡入淡出叠在同一批帧里就是卡顿的来源，与 CPU 算不算得过来无关。

- **打开 Emby 条目**：先让侧栏滑出（`EmbyDetail.sidebarHandoffDelay` 0.45 s，父级页面先进入无侧栏状态），再推入详情页；返回时先弹出详情页，0.45 s 后侧栏再滑回。推入与宽度变化不落在同一批帧。
- **Emby 详情页**：进入后页面为空；`refresh()` 完成、前 `entrancePrefetchCount`（12）张子条目封面解码完成、背景图解码完成（最多等 1.5 s）之后一次性揭示：背景图只淡入（0.4 s），之后静止 `heroEntranceDelay`（0.5 s）让佩戴者看一眼大图；然后标题、类型行、简介、技术行、操作行、剧集架、Special Features、Related、演职员、关于按同一个动画（`entranceDuration` 0.35 s，从下方 `entranceTravel` 40 pt 滑入）以相等间隔 `entranceStagger`（0.15 s）从上到下依次进入。hero 背后的 `titleWash`（椭圆压暗）随标题一起淡入——等待期间它不能先出现，否则空页上悬着一大块软阴影。背景图不设解码上限，其它封面维持 1024 px。
- **Emby 海报网格**（换分类、搜索）：`isLoading` 期间不渲染网格；条目到齐后网格以 opacity 0 建立并完成布局，下一帧用 `gridRevealDuration`（0.25 s）淡入——把未解码的网格直接放进正在跑的淡变里会卡（2026-09-05 真机）。前 `gridRevealPrefetchCount`（24）张海报的预取与这次揭示并行（`async let`），不再挡在它前面：门控的对象是结构数据而不是像素，海报自身有占位，而等 24 张图片下完会把页面留空到最慢那张为止。`isLoading == false` 同时经 `.levelReadiness` 上报，层级因此等条目到齐才淡入，而不是先淡入一张空页再填。
- **Files 的文件夹层级**：`FileBrowsingViewModel.currentLevelHasSettled` 经 `.levelReadiness` 上报，落定之前页面渲染 `loadingState`。这个转圈被层级门控压在透明状态，只有空白超过 0.4 s 才真的出现；清单在那之前到达时，佩戴者看到的是一次淡入，中间没有转圈闪一下。

## 卡片 hover 揭示

`GridCard` 四种变体在注视下揭示的东西一致：观看进度条只在 hover 时出现（video、poster、episode 都经 `watchedProgressBar`，不直接画 `watchedEdgeProgressVisual`）；video 与 episode 的说明块经同一个 `thumbnailCaption`（scrim、底左对齐、hover 显隐）和同一个 `captionBlock`；episode 的块是标题两行、简介、`play.fill` 时长，video 的块是一行：左边 `play.fill` 加时长（来自观看状态里的 `durationSeconds`，格式与 Emby 相同，未知时留空）、右边体积——文件名已经在缩略图下方，块里不再重复。scrim 由 `thumbnailTextScrim` 画，覆盖缩略图底部 `Surface.textScrimCoverageFraction`（0.8）、在顶部 20% 处消失：文字块下半段（`Surface.textScrimPlateauFraction` = 0.4）是材质满段，满段之上直到遮罩顶（缩略图 80% 处）全部给渐变（0 → `textScrimOpacity` 1，缓入缓出）。渐变区随文字块变矮而变长，短文字得到最柔的过渡；把渐变压在文字上或塞进固定 47 pt 的延伸段都被否决——前者让长说明的标题落在最淡处，后者在长说明上把过渡压成一条线。`ScrimKeyframe.stops` 采样 24 段成 stop；被 mask 的不是黑色而是 `Surface.textScrimMaterial`（ultraThickMaterial）——黑色压暗在亮封面上要到 0.5 才能让白字可读，而人眼对低亮度区域敏感，材质用模糊加自适应对比让文字从杂乱封面里分离出来，不靠压暗。缓出（起点斜率最大）被否决，它在顶端留一条马赫带分界线；三段关键帧（0.25 处 0.36 再线性到 0.4）在有了高度下限之后不再需要。曲线处处光滑，文字块多高都只是同一条曲线的缩放，短文字块不会出硬边；0.9 的底部密度与指数 3 的缓入缓出都被否决：一行文字的块里高指数就是硬边。手放的三个 stop 是折线：拐点与起点在 180 pt 的块上看不见，压进 70 pt 就是一条硬边——2026-09-05 同一 Emby grid 里有简介与无简介两张卡因此长得截然不同。Emby 原来的卡片相对渐变（25%／50%／100%）同样是折线，只是永远摊在 205 pt 上。此外 Emby 里没有文字块上方的引入段；「块高 × 2」与「固定 52 pt 引入段」两版都被否决，一行体积上方任何引入段都会让黑色明显超出文字。2026-09-05 真机否决了"角落一行体积＋半张卡的 scrim"：Files 与 Emby 的 hover 必须是同一个说明块。folder 的缩略图是平面，不需要 scrim。同一个守卫脚本钉住这些结构。
## 系统 Menu 里哪种行留得住标识符

**系统 Menu 的内容随宿主 body 一起重建**：宿主窗口的 body 每重新求值一次，UIKit 就重建一次菜单并重新呈现已打开的子菜单。播放窗口的根 body 曾因 `.accessibilityValue` 快照读取每帧更新的播放位置而按播放时钟重算，三级菜单因此闪烁到无法点中；读取高频运行时属性的快照必须住在自己的 `ViewModifier`／子视图里（`WindowControlPlaneStateModifier`、`PlaybackAutomationStateProbe`），Observation 的失效范围就只有那一个节点。同理，菜单内容的 `onAppear` 不能改写被宿主 body 读取的状态：`setControlsFocused` 只在焦点值真正改变时登记一次交互。两条都由 `Scripts/rules/verify_playback_surface_structure.py` 钉住。

`.accessibilityIdentifier` 只保留在菜单当作一等 action 采纳的行上。`Picker` 行与 `Toggle` 行都是菜单自行布局的内容，二者到达 accessibility 树时**完全没有标识符**，任何东西都寻址不到它们，覆盖率检查也不会因此变红；`Button` 行保留标识符。三者在 2026-08-21 于设备上同一构建里实测。

代价是勾选标记的位置：`Picker` 把它画在尾缘，`MenuSelectionRow` 画在前缘。未选中行不能没有图标，否则标题相对选中行左移一个图标位；`MenuCheckmark.image(isSelected:)` 给未选中行一张 `.alwaysOriginal` 的透明 checkmark（`UIImage.withTintColor(.clear)`），菜单为每一行保留图标列，标题对齐。`.hidden()`／`.opacity(0)` 在 SwiftUI→UIMenu 桥接时会被丢弃，所以必须是一张真实的透明图。

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
- **圆形不定式（advance）动画常数**取自 material-components-android 的 `CircularIndeterminateAdvanceAnimatorDelegate`，放在 token 里，而不是在视图里重新编码一遍周期。
- **字体一律走 `Typography` 语义映射，不用 `.system(size:)`**：系统 Text Style 自动处理 Dynamic Type 与 visionOS 的观看距离。
- **scrubber 的抓取区**比拇指宽得多。拇指按轨道高度绘制以便读作轨道的一部分，那远小于佩戴者能命中的注视目标，因此启动 scrub 并显示注视高亮的区域另有宽度（`thumbGrabWidth`）；"算点击而不算拖拽"的位移上限（tap slop）与它是两个概念，取得很小，任何有意的拖拽都会超过它。
- **详情页背景图向服务器请求的像素数**是限定值：原图是整幅制作剧照，解码它正是进入页面时卡住的原因。
- **按压反馈按面积分级**：大面积表面动得最轻，卡片才在空间里保持稳定；行的位移更小，否则密集列表读起来发跳；控件胶囊因为彼此隔离可以响应得更明显；单个图标用最强的缩放线索，与空间胶囊控件一致。

## 滑块与开关尺寸

`CenterSlider`、`RangeSlider` 与 toggle 共用 `Interactive` 的轨道高度和旋钮尺寸。共享尺寸在 token 中定义，组件内部不重复声明。
