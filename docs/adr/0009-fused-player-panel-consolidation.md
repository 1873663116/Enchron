# ADR-0009：融合播放面板收口（FusedPlayerPanel 取代 deck + 设置面板）

- 状态：**决策已定，落地中（2026-06-21 立档）**
- 日期：2026-06-21
- 决策者：项目负责人（经一轮 /grill-with-docs 盘问逐叉定案）

## 背景

窗口播放此前由**两个独立 ornament** 承载：
- 底部 `PlayerControlDeck`（transport + 进度/精密时间轴 + ⋯ 菜单），由 `PlayerControlDeckLive` 注入真实播放（`onSeek`/`onSkip*`/`onPlayPause`/`onFrameStep` + live `progress`/labels/fps/replay）；定义在 `XrPlayer/Shared/Components/SharedComponents.swift`，主 App 经 `WindowPlayerDeck.swift` 注真、DesignPreview 走默认 mock 路径。
- 前缘 `PlaybackSettingsPanel`（`CategorySidebar` + `SettingListGroup`），直读 `@Environment(AppModel.self)`，绑 Play Mode（window/immersive/panorama → 沉浸空间进出）、环境、曲面屏、Picture；由 `MainView.swift` 的 leading ornament 挂载，`appModel.showPlayerSettingsPopup` 控制。

DesignPreview 这一轮把这两块重做成**一个会形变的 `FusedPlayerPanel`**：单块玻璃壳内含控件 + 时间轴 + 设置，状态机为「≡ 开关设置、双击进度条开/收时间轴、两者独立可并存」。负责人认定该形态为定稿,要求让它进化为正式组件、取代 deck + 设置面板,并改主 App。

冲突在于:`FusedPlayerPanel` 当前是 Canvas mock(无 `live` 注入、⋯ 无菜单、设置区内容与生产语义不一致),直接删旧换新会让真实播放与 UI 测试退化。

## 决策

**以 `FusedPlayerPanel` 为唯一窗口播放面板,整壳取代 `PlayerControlDeck` + `PlaybackSettingsPanel`。** 落地约束:

1. **整壳替换(方案 A)**:FusedPanel 同时吃掉底部 deck 与前缘设置 ornament;`MainView` 撤掉 leading 设置 ornament,设置改为从底部面板内联形变长出。
2. **控件行模式入口重分配**:左 `[≡ 设置][⤢ 全景]`、中 `[⏪][▶][⏩]`、右 `[🧘 虚拟场景][⋯ 菜单]`(🧘 为新增,补平左右不对称)。
   - ⤢ → `updatePlaybackMode(.panorama)`;🧘 → `updatePlaybackMode(.immersive)`(打开**默认**场景,**不带选场景语义**)。切场景按钮将来建在虚拟场景内部、开 EnvironmentCard volume——本轮不做。
3. **设置区接线分三桶**:
   - **接真后端**:Display Mode(Flat/SBS/TB)→ `stereoLayoutOverride`;180/360 → `projectionOverride`。
   - **honest-fake(可交互但 inert,标 `// FAKE:`,接管真后端时再接)**:Environment **Day/Night + Auto**(语义=场景内昼夜,**非**切场景,现无后端状态)、屏幕 Curve/Height/Distance/Size 四滑块、Position、Picture 全套 libplacebo。
   - 注:曲面屏/屏幕几何本轮一并做 fake(放弃生产原有的曲面屏 on/off 绑定),留待接管步统一接真。
4. **注入式拿绑定**:FusedPanel 通过注入结构(默认 mock → DesignPreview 可 Canvas 渲染;主 App 注 `appModel`/`WindowVideoViewModel`)取得播放与设置绑定,**不直读 `@Environment(AppModel.self)`**——守 DesignPreview「组件必须能在 Canvas 渲染」规则。
5. **测试改写**:UI 测试 ID 由 `DesignPreview-PlayerControlDeck-*` 统一为组件自有稳定前缀 `PlayerPanel-*`,断言新状态机;不再触及旧组件。
6. **删除**:旧 `PlayerControlDeck` + `PlayerControlDeckLive`、`PlaybackSettingsPanel`、DesignPreview `PlayerSettingsPanelPreview` 及其 showcase 引用。

落地顺序(每阶段可回退、模拟器截图验证):① 运行验证现状四态 → ② 固化为共享组件 + 接桶①③/⋯/🧘 → ③ 改主 App(WindowPlayerDeck + MainView 撤 ornament + 整合自动隐藏)→ ④ 改测试 → ⑤ 删旧 + DesignPreview 收口 → ⑥ 文档(本 ADR + plan/use_cases/CONTEXT + doc-auditor)。

## 考虑过的替代方案

- **方案 B(只换 deck,前缘设置 ornament 保留)**:改动面小、不碰沉浸切换。否决理由——负责人定稿的就是「设置内联形变」的整壳形态,保留两 ornament 等于不采纳定稿。
- **设置区内容以生产语义为准(Window/Immersive/Panorama 三选卡 + 真实三场景)**:否决——模式切换已重分配给控件行两按钮;Environment 经澄清是场景内昼夜而非切场景,故沿用 Day/Night 定稿设计。
- **无后端行做只读或删除**:否决——本轮为「前端定稿、接模拟管线」,留住定稿交互形态最忠实;只读丢手感、删则缩小定稿面。

## 后果

- 主 App 窗口播放 chrome 由「双 ornament」简化为「单形变面板」;`showPlayerSettingsPopup` 语义并入面板内部 `settingsPresented`。
- 曲面屏/屏幕几何在本轮**暂失真实绑定**(降为 fake),需在后端接管步补回——这是已知的、被接受的临时退化,记于此。
- 切场景(EnvironmentCard volume)为显式未来工作,跨表面流程留给 FakeApp/接管步。
- 退役 `PlayerControlDeck` / `PlaybackSettingsPanel` / `PlayerSettingsPanelPreview`;`PlayerControlDeckLive` 的注入接口并入 FusedPanel 的注入结构。
