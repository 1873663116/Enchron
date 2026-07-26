# Enchron macOS 端到端测试矩阵

本矩阵定义 `EnchronMacOS` 的真实用户端到端（End-to-End，E2E）验收。测试必须从生产 App 的可见界面进入来源、选择真实媒体并完成播放操作；构建成功、直接设置 `ENCHRON_AUTOPLAY_FILE`、调用产品内部方法或只读取 PlaybackCore 状态都不能替代本矩阵。

macOS 是 Enchron 的近产品开发宿主。它可以证明共享来源、Media Library、SwiftUI、`PlaybackRuntime`、PlaybackCore、RealityKit consumer 和可移植交互，但 macOS 的 Panorama 只是 Window consumer simulation，不能证明 visionOS `ImmersiveSpace`、最终投影几何、空间舒适度、硬件 HDR/EDR 或 Vision Pro 音频。

## 证据边界

- **真实 UI 输入**：Computer Use 读取当前屏幕与 Accessibility tree 后，通过真实鼠标、键盘、滚动或拖动完成操作；无人值守驱动可以用 Accessibility 定位，但必须向元素实际几何发送操作系统输入并经过正常 hit testing。`XCUIElement.click()`、Accessibility `press`、内部 command 或 ViewModel 调用在未证明命中同一生产 UI action 前只能作为辅助证据，不能计入 E2E。除系统文件面板等没有 App identifier 的界面外，不使用预先写死的屏幕坐标。
- **无人值守回归**：XCUIAutomation 或确定性的 AX + `CGEvent` harness。语义元素没有可用几何时立即失败；不能盲点固定坐标。
- **机器 oracle**：Accessibility 后置状态、`PlayerUI-playback-state`、PlaybackCore `snapshot.json`/`events.jsonl`、OSLog、远程服务器访问日志、媒体 hash 和进程退出状态。日志无错误本身不等于通过。
- **视觉证据**：每个状态变化保存点击前、点击后截图；播放还需两个有时间间隔的画面或短录屏证明可见画面持续变化。普通电影画面只能证明可见播放，不是投影、立体或色彩的 Visual Oracle。
- **真实世界媒体**：直接来自 workspace 根 `../TestMedia/` 的现有媒体；不能用项目生成 fixture 冒充真实世界媒体兼容性。
- **确定性媒体**：`docs/acceptance/fixture-registry.json` 中的项目生成 fixture 只用于时间、字幕、颜色信令等可计算 oracle；不能替代真实世界媒体旅程。
- **远程来源**：SMB 使用与 Local 逐字节一致的完整 fixture corpus；只读 WebDAV 使用夸克现有媒体建立独立的不可变 registry，记录稳定路径、大小、hash、媒体事实和能力覆盖。只有实际 hash 相同的对象才断言跨来源字节身份；否则分别证明来源旅程与共用播放合同。`file://`、直接打开共享目录的本地挂载路径或 App 内 mock 不能算远程来源。localhost AList/SMB 可以证明协议实现，但必须标记 `loopback`，不能冒充跨主机网络证据。

## 运行层级

| 层级 | 运行时机 | 必须覆盖 | 通过条件 |
|---|---|---|---|
| P0 | 每次修复后的首轮和提交前 smoke | 宿主预检；Computer Use 完整点击一次；从 `TestMedia` 真实 Add Files 并播放；WebDAV/AList 播放；SMB 播放；播放/暂停、前后跳转、seek、Back | 同一 revision 连续 3 次全绿；不允许人工补做步骤、自动重试或未分类失败 |
| P1 | 夜间完整回归 | 所有来源旅程；Media Library；全部可达播放控件；来源持久化与重启；远程异常；真实媒体兼容矩阵；设置持久化 | 每个旅程至少跨 2 次全新 App 启动通过；Accessibility 动作清单没有未覆盖的新控件 |
| P2 | 里程碑、发布前或高风险播放改动 | 长媒体、格式/容器扩展、断网恢复、快速连续操作、反复开关/切源、内存与 CPU、结束行为 | 运行 manifest 规定的完整时长完成；无 crash、hang、资源无界增长、未分类错误；失败修复后从最初前置状态稳定重放 |

P0 不是单元测试集合，而是三条真实来源到播放的最短闭环。本矩阵不因某个远程服务暂时不可用而把用例标为 skipped；该结果应分类为 `endpoint` 或 `host`，本轮 P0 仍未通过。

## 宿主硬门槛与持久证据

每轮运行使用唯一 `run-id = <UTC timestamp>-<Enchron short SHA>-<sequence>`。正式证据不得只保存在 `/tmp`；固定根目录为：

```text
../TestMedia/e2e-evidence/macos/<run-id>/
├── manifest.json
├── host-preflight.json
├── actions.jsonl
├── screenshots/
├── recordings/
├── app/
│   ├── oslog.logarchive
│   ├── events.jsonl
│   ├── snapshot.json
│   └── crash-reports/
├── sources/
│   ├── local.json
│   ├── webdav-server.log
│   ├── smb-server.log
│   └── remote-staging-manifest.json
├── tests/
│   └── EnchronMacOSE2E.xcresult
└── result.json
```

运行前必须把 PlaybackCore 在临时目录生成的 live debug 文件复制到上述目录。`manifest.json` 至少记录 Enchron revision 和 dirty patch hash、macOS/Xcode/Swift/FFmpeg 版本、App bundle hash 与签名 identity、driver、测试层级、显示配置、端点拓扑、媒体相对路径/大小/SHA-256、开始和结束时间。缺少任一项时，本轮最多是 diagnostic。

预检必须在启动 App 前证明：目标 App 是本轮构建；Accessibility、Screen Recording 和 Post Event 可用；Automation Mode 可用；没有旧 Enchron 进程；证据目录可写；WebDAV 与 SMB 端点可连接；SMB staging manifest 与 Local hash 一致；WebDAV registry 中计划对象的路径、大小和 hash 未漂移；所有计划媒体仍存在。预检失败归入宿主或端点故障，不启动产品断言。

## 交互驱动与动作记录

每条 P0 来源旅程至少执行一次 `computer-use` 驱动；P1/P2 的稳定重跑使用 XCUIAutomation 或现有 `Scripts/verification/macos_ui_acceptance.swift` 扩展后的 AX + `CGEvent` 驱动。两类结果分别记录，不能把 agent-assisted 通过改写成无人值守回归通过。

`actions.jsonl` 每个动作一行，包含：

```json
{
  "scenario": "LOCAL-01",
  "step": 4,
  "precondition": {"screen": "media-library", "item": "absent"},
  "driver": "computer-use",
  "target": {"identifier": "FileBrowsing-Manage-button", "label": "Manage media library"},
  "operation": "leftClick",
  "beforeScreenshot": "screenshots/LOCAL-01-04-before.png",
  "afterScreenshot": "screenshots/LOCAL-01-04-after.png",
  "oracle": {"identifier": "MediaLibrary-Manage-addFiles", "exists": true},
  "status": "passed"
}
```

一次“点击成功”必须同时具备可追溯目标、输入事件和后置条件。只有鼠标移动、按钮高亮、菜单消失或请求已经发出不能算通过。系统 Open Panel 记录 AX role/title、选择的规范化 URL 和确认后的 Media Reference；密码不得写入 action、截图、OSLog 或服务器日志。

禁止在来源 E2E 设置 `ENCHRON_AUTOPLAY_FILE` 或 `ENCHRON_UI_TESTING`。允许设置只增加只读可观察性的 `ENCHRON_AUTOMATION_PROBE=1`；它不得创建媒体、选择来源、改变状态机或替代可见 UI。

## Accessibility identifier 映射

下列 identifier 是当前生产代码的语义入口。动态值以运行 manifest 中发现的实际名称/UUID 展开；系统界面没有 App identifier 时使用 AX role、标题与选中 URL。

| 表面 | 当前 identifier 或稳定标签 | 用途 |
|---|---|---|
| 主导航 | `Navigation-Ornament-tab-files`、`-settings`、`-environment` | 切换 Files、Settings、Environments |
| Files 根 | `FileBrowsing-FilesScreen`、`FileBrowsing-MainWindow-sidebar` | 判断浏览器已出现 |
| 来源操作 | `FileBrowsing-SourcesSidebar-sourceMore`、`-addFiles`、`-addWebDAV`、`-addSMB`、`-refresh` | 打开系统文件面板、添加或刷新远程来源 |
| 已保存来源 | `FileBrowsing-SourcesSidebar-source-<data-source UUID>` | 选择并重连保存来源；UUID 写入运行 manifest |
| 远程连接表单 | `FileBrowsing-SourceConnection-name`、`-address`、`-share`、`-guest`、`-username`、`-password`、`-connect`、`-error` | WebDAV/SMB 新建、认证与错误反馈 |
| Media Library 操作 | `FileBrowsing-Manage-button`、`MediaLibrary-Manage-addFiles`、`-addFolder`、`-addPhotos`、`-newFolder` | 建立本地/Photos 引用和 Library Folder |
| Library 对象 | `MediaLibrary-grid-folder-<name>`、`MediaLibrary-grid-video-<name>` | 打开虚拟目录或播放引用 |
| 远程对象 | `FileBrowsing-grid-folder-<name>`、`FileBrowsing-grid-video-<name>` | 浏览远程目录或直接播放远程文件 |
| 浏览操作 | `FileBrowsing-FilesScreen-navBackForward`、`-viewMode`、`-sort`、`-search`、`FileBrowsing-Breadcrumb-button-<index>` | 导航、显示、排序、搜索 |
| 新建/重命名 | `MediaLibrary-NewFolder-name`、`-create`、`MediaLibrary-RenameFolder-name`、`-confirm` | Library Folder 生命周期 |
| 播放根与状态 | `PlayerUI-window-playback`、`PlayerUI-window-control-plane`、`PlayerUI-playback-state` | 可见播放和只读机器状态 |
| 播放控制 | `PlayerPanel-button-expand`、`-rewind`、`-play`、`-forward`、`PlayerPanel-thumb` | 时间线、逐帧、transport、seek |
| 播放菜单 | `PlayerPanel-menu-more`、`-subtitles`、`-audio`、`-speed`、`-episodes`、`PlayerPanel-menu-<category>-<item id>` | 字幕、音轨、速度、剧集 |
| 呈现 | `PlayerUI-TopAction-dock`、`PlayerUI-DockMenu-<day|night>`、`PlayerUI-TopAction-videoFormat`、`PlayerUI-VideoFormat-<group>-<option>`、`-apply`、`PlayerPanel-button-exit-spatial`、`PlayerPanel-button-back` | Window/Docked/Panorama 与返回语义；Deck 不出现 Dock/Panorama 入口 |
| Docked placement | `PlayerPanel-ScreenSize-slider`、`PlayerPanel-Distance-slider`、`PlayerPanel-Elevation-slider`、`PlayerPanel-DockedPlacement-reset` | 尺寸、用户中心距离、球面仰角、始终朝向用户与默认值恢复 |
| 退出播放 | `PlayerUI-InfoBar-button-back` | close 当前 session 并回到浏览器 |
| 播放覆盖层 | `PlayerUI-resume-primary`、`-secondary`；错误面板以运行时发现的 `PlayerUI-loadFailure-*` 为准 | 续播、从头、失败和重试 |
| Settings | `Settings-SettingsScreen`、`Settings-category-<playback|spatial|storagePrivacy|about>`、各 `Settings-*-group` | 设置分类与持久化 |

P1 运行在 Files、Settings、Window、Docked 和 Panorama simulation 的每个稳定状态抓取所有可交互 AX 元素，并与版本化动作清单比较。新增的 button、menu item、slider、toggle 或 text field 没有矩阵条目时，本轮结果为 `coverage-gap`，不能继续宣称“每个按钮已测试”。当前缺少稳定 identifier 的设置行和部分 context menu 项以可见 label 定位，并将“补 identifier”记录为可测试性缺口。

## 来源与用户旅程矩阵

| ID / 层级 | 前置状态 | 真实用户操作 | 机器 oracle | 视觉证据 | 主要失败分类 |
|---|---|---|---|---|---|
| NAV-01 / P0 | 全新启动，未播放 | Computer Use 依次点击 Files、Settings、Environments，再回 Files | 对应根表面出现；选中 trait 唯一；无空白页面 | 每个 tab 点击后截图 | product-ui、permission、coverage-gap |
| LOCAL-01 / P0 | Media Library 清空；`../TestMedia/Apple/IMG_6340.MOV` 存在且 hash 已登记 | 点击 Manage → Add Files；在系统 Open Panel 逐级进入 `../TestMedia/Apple`，选择文件并 Open；点击新增 `MediaLibrary-grid-video-IMG_6340.MOV` | Media Reference locator 为 security-scoped bookmark；生命周期到 playing；session 非 none；两个采样点 position/frame 递增；Back 后 session cleanup 且引用仍存在 | Open Panel 路径、Library 卡片、首帧、持续播放、Back 后浏览器 | product-source、product-playback、system-panel、permission |
| LOCAL-02 / P1 | Library 清空；`../TestMedia/CodecContainerMatrix` 可读 | Manage → Add Folder Contents；在 Open Panel 选择目录；搜索一个文件、切 grid/list、排序并播放；退出 App 后重开并再次播放 | 只创建 Media Reference，不复制媒体；引用数与可播放文件集合一致；bookmark 在重启后解析原路径；原目录 inode/size/hash 不变 | 选择目录、导入结果、搜索/排序、重启后卡片和播放 | product-library、product-source、system-panel |
| LOCAL-03 / P1 | LOCAL-01 引用已持久化 | 暂时使源不可访问后点击引用；在错误 UI 点击恢复/确认；恢复源后重试 | 不创建第二 session；错误可恢复；引用没有被删除；恢复后建立新 session 并播放 | 错误、恢复动作、成功首帧 | product-source、permission、test-data |
| WEBDAV-01 / P0 | 只读夸克 WebDAV registry 已固定；Library 不含该来源 | Computer Use 点击来源 More → Add → WebDAV；填写名称、URL、用户名和密码并 Connect；逐级点击远程文件夹和真实媒体卡片 | 来源保存且凭据只进入 Keychain；目录来自真实 PROPFIND；播放产生 GET/Range；对象路径、大小和 hash 等于 WebDAV registry；position/frame 递增；seek 产生符合实现的后续 range 访问；不修改远端内容 | 表单（密码遮盖）、远程目录、播放前后帧、seek 后画面 | product-remote、credential、endpoint、network |
| WEBDAV-02 / P1 | WEBDAV-01 来源已存在 | 对远程文件执行 Add to Media Library；回 Media Library 播放；退出重开后从引用播放；刷新来源 | locator 为 source ID + 远程路径；重启后从 Keychain 重连；没有把整个媒体复制进 App container；服务器日志可关联两次 session | 加入前后、Library 卡片、重启后播放 | product-library、product-remote、credential |
| WEBDAV-03 / P1 | 有可控 AList/WebDAV 认证与进程 | 依次输入错误密码、停止服务、播放中断开服务、恢复服务后点击 Retry | 错误分别收敛到认证、连接/超时、读取失败；没有 hang 或静默切本地路径；失败 session cleanup；恢复后新 session 成功 | 每类错误与 Retry 前后 | product-error-ui、product-remote、endpoint、network |
| SMB-01 / P0 | macOS File Sharing 或测试 SMB 服务暴露同一 remote staging share | Computer Use 点击来源 More → Add → SMB；填写 address、share、guest 或用户名/密码并 Connect；浏览目录并播放真实媒体；pause、seek、resume | 保存 SMB source；列目录和 byte-range/read 发生在 SMB 服务；播放对象 hash 与 staging manifest 一致；同 session 完成 pause/seek/resume | SMB 表单、目录、首帧、seek 后帧 | product-remote、credential、endpoint、network |
| SMB-02 / P1 | SMB-01 来源已保存 | Add to Media Library；退出 App；重开并从引用播放；刷新；删除来源后点击残留引用 | 重启可从 Keychain 重连；删除来源不删除共享文件；残留引用明确失败而非播放错误对象；共享源 hash 不变 | 重启播放、删除来源、残留引用错误 | product-library、product-remote、credential |
| SMB-03 / P1 | SMB 服务支持切换 guest/认证、停止和恢复 | 错误 share、错误密码、运行中断开、恢复后 Retry | 错误分类准确；没有凭据泄漏、死锁、无限 spinner 或隐藏 WebDAV/file fallback；恢复后新 session 播放 | 四类状态截图/短录屏 | product-error-ui、product-remote、endpoint、network |
| REMOTE-IDENTITY-01 / P0 | Local 与 SMB 由同一 staging manifest 创建；WebDAV registry 已固定 | 分别从 Local、SMB 打开同一相对路径，并从 WebDAV 打开登记对象 | Local/SMB 的 SHA-256 与大小一致；WebDAV 对象与自身 registry 一致；三条来源分别记录 locator/provenance；产品路线均为 FFmpeg compressed，不因来源切换 route。只有 WebDAV 对象 hash 实际相同时才增加三来源字节等价断言 | 三次媒体标题和首帧 | test-data、product-source、product-playback |

系统级“磁盘已经挂载”的 Finder 路径只能用于准备或人工核对 SMB 服务；若 Enchron 实际收到的是本地 `file://` URL，结果只能计入 LOCAL，不能计入 SMB。

## Media Library、设置与完整控件矩阵

| ID / 层级 | 前置状态 | 真实用户操作 | 机器 oracle | 视觉证据 | 主要失败分类 |
|---|---|---|---|---|---|
| LIB-01 / P1 | Media Library 根，至少两个引用 | New Library Folder；输入名称并 Create；重命名；进入目录；把引用移入；搜索；返回；移除目录并确认 | 文件夹层级和引用关系按操作持久化；原始文件/远程对象 size/hash 不变；移除只删除引用 | 每个结构变化前后 | product-library、coverage-gap |
| LIB-02 / P1 | 本地、WebDAV、SMB 来源均已保存 | 选择来源、进入子目录、breadcrumb 返回、back/forward、refresh、grid/list、name/date/size 与升降序切换、搜索 | 路径栈和选择状态唯一；刷新不重复对象；排序结果与元数据一致；搜索结果全集正确 | 每种视图及排序结果 | product-ui、product-remote、coverage-gap |
| SETTINGS-01 / P1 | 非播放状态 | 进入四个 Settings category；逐项选择 Resume、End、Default Speed、Auto-Hide、Default Environment Appearance；退出并重启 | UserDefaults/产品状态与可见选项一致；Day/Night 不产生第二个 Environment identity；设置不会创建 Media Session | 每个 category 与重启后的选中值 | product-settings、coverage-gap |
| SETTINGS-02 / P1 | cache/progress 均有可测数据 | 点击 Clear Thumbnail Cache、Clear All Progress、Copy Version、Copy Feedback、View Licenses 和 Done | cache/progress 的指定数据清除且原媒体不变；剪贴板内容精确；licenses sheet 正常关闭 | 操作前后值和 sheet | product-settings、permission、coverage-gap |
| PLAY-01 / P0 | LOCAL-01、WEBDAV-01 或 SMB-01 已 playing，剩余时长 > 30 秒 | 点击 Pause、Rewind 10s、Forward 10s、Play，拖动 Progress Bar thumb 后释放，最后 Back | lifecycle 与 label 在 playing/paused 间收敛；Progress Bar seek 后 playing；position 在容差内到目标；旧 seek epoch 不再更新 UI；同一 session；Back 后 controls 消失并完成 cleanup | 每步截图和一次 Progress Bar 拖动录屏 | product-control、product-playback、input |
| PLAY-02 / P1 | 含双音轨、字幕且可逐帧的媒体 | 展开面板；点击前一帧/后一帧；拖 precision timeline 和 zoom；收起；More 中遍历字幕、音轨、全部速度与可用 episode | frame step 只改变一帧语义；timecode/position 一致；每个菜单选择投影到当前核心状态；音轨/字幕切换不换 session；速度恢复 1× | 展开/收起、每类菜单、字幕像素、轨道切换短录屏 | product-control、product-track、coverage-gap |
| PLAY-03 / P1 | 同一 Media Identity 与 Content Revision 有有效 Resume | 再次点击媒体；分别执行 Resume、Start Over | Prompt 只有 Resume 与 Start Over，没有 Cancel；Resume 从保存点容差内开始；Start Over 从零开始；格式偏好在决策后应用 | 两个 overlay 结果 | product-policy、product-playback |
| PLAY-04 / P1 | 短媒体接近结束 | 依次在 Stop、Loop Single Episode、Play Next 设置下播放到结束；在 Stop 下召唤 Deck，检查 Replay、前后 10 秒，展开 Advanced Settings 检查前后帧并操作 Replay | ended 仅在 active lanes 完成后发布；Stop 保留同一 Media Session 与纯黑画面，不自动显示控件；Replay 与后退可用，结尾处前进禁用；Advanced Settings 可打开，上一帧可用而下一帧禁用；Replay 在同一 Session 从零开始；repeat、next 各自执行且不出现两个 active session | 结束前后、Stop 控件状态、下一项/重播 | product-policy、product-playback |
| PRESENT-01 / P0 | Window playing | 点击 Dock → Day/Night；在 Docked 调 Screen Size、Distance、Elevation、Restore Defaults；Return Window；打开 Panorama，选择 360° × Mono 并 Apply；Return Window 后再次点 Panorama；最终 Back | 全程同一 Media Session；Window/Docked/Panorama binding 唯一；Day/Night 共用 placement；返回 Window 保留 panoramic format、隐藏 Dock，Panorama 按钮直接恢复；Back 才结束播放 | Window、Docked、placement、Panorama、返回与最终 Library | product-presentation、product-control |
| PRESENT-02 / P1 | Window playing，使用 Flat/Mono 普通媒体 | 遍历 Projection 与 Stereo Layout 可见选项并 Apply；分别用缺少和包含 AIME 事实的媒体检查 Fisheye | 缺少 AIME 时不显示 Fisheye；包含 AIME 时仅解锁选项、不自动选择或应用；格式 revision/错误符合来源事实；失败保持 Window 和同一 session | 每个菜单选择及失败反馈 | product-format、product-error-ui |
| ERROR-01 / P1 | 准备不支持/损坏或暂时不可读的 TestMedia 对象 | 通过 UI 选择对象；点击 Retry 和 Close/Back | 第一个失败节点、error domain/code 和 cleanup 可关联；无隐藏替代媒体管线；Retry 行为确定 | 失败、Retry、返回 | product-source、product-playback、test-data |

同一控件如果在 Window、Docked、Panorama simulation、playing、paused、ended、loading、failed 中语义或可用性不同，必须在对应稳定状态分别记录。禁用控件需要断言其不可操作及原因；不存在的能力不能通过点击无反应来算覆盖。

## TestMedia 真实媒体矩阵

`../TestMedia/fixture-registry.local.json` 目前含旧绝对路径和历史仓库信息，不能作为当前通过依据。首次执行前必须根据当前相对路径重建 remote staging manifest：记录大小、SHA-256、`ffprobe` container/codec/profile、duration、轨道、color/HDR/projection/stereo 事实、许可边界和期望结果。未知事实保持 unknown，不能从目录名推断。

| 类别 | 当前相对路径 | 层级与用途 | 最低断言 |
|---|---|---|---|
| Apple 相机 MOV | `Apple/*.MOV` | P0 使用 `IMG_6340.MOV`；P1 全部 | Add Files、可见持续播放、seek、reopen；实际 metadata 以新 registry 为准 |
| Dolby Vision | `DolbyVision/{SD,HD,FHD,UHD}/*.mp4` | P1 每个 P5/P8.1/P8.4 至少一个分辨率；P2 全部 | Provider/sample/displayed pixel 信令和可见推进分别记录；macOS 不宣称 Vision Pro HDR 观感 |
| HDR10/PQ | `HDR10/HDR10.MP4`、`HDR10/*.mkv` | P1 MP4；P2 MKV/长媒体 | BT.2020/PQ/range 机器事实、持续播放、seek、资源稳定性 |
| HLG | `HLG/*.ts`、`HLG/01. TS Files/*`、`HLG/02. MP4 Files/*` | P1 一个 TS + 一个 MP4；P2 patch 全集 | HLG signaling、TS/MP4 container、可见推进；patch 普通截图不作色准结论 |
| Codec/container | `CodecContainerMatrix/{AV1,H264,MPEG4-Part2}/**` | P1 每个 codec 至少一项；P2 全部 container | 成功则记录真实 route/sample/播放；不支持则稳定失败并记录首失败节点，不以“能打开”代替播放 |
| Panorama 实拍 | `Panorama/*.mp4` | P1 来源与 Window 播放；P2 格式操作 | 在 macOS 只证明媒体可读与 Panorama simulation 状态，不证明最终全景投影 |
| 3D 实拍 | `3d/*.mp4` | P2 | 来源、stereo metadata/override 与播放；macOS 截图不证明双眼方向正确 |
| 校准/派生 | `calib/*`、`_derived/**/*` | P1/P2 diagnostic | 只在有明确 Visual Oracle 时证明几何/方向；不得算作真实世界兼容样片 |
| 历史 L3 证据 | `l3-evidence/**` | 不执行 | 只作历史参考，不反推当前 revision 通过 |

矩阵中的每个真实媒体结果必须是 `passed`、`expected-unsupported`、`product-failed`、`infrastructure-failed` 或 `not-run` 之一。只有 registry 已记录许可和 oracle 的媒体才能让正式 acceptance 行变绿；其余结果标为 diagnostic，但发现的 crash、hang 或错误恢复问题仍是有效产品缺陷。

## Local/SMB 同源 corpus 与只读 WebDAV registry

Local 直接使用 `../TestMedia`；SMB 把相同字节复制到本轮隔离目录 `../TestMedia/e2e-staging/<run-id>/media/` 并通过生产 SMB adapter 暴露。首轮快速闭环使用下列子集，完整矩阵按 registry 扩展到整个 corpus：

```text
Apple/IMG_6340.MOV
DolbyVision/SD/Patterns_Of_Nature_DoVi_24_P5_SD_HEVC-1mbps_DD+JOC-768kbps_iOS.mp4
DolbyVision/SD/Patterns_Of_Nature_HDR10-P8.1_SD_24_H265-1Mbps_DD+JOC-768Kbps.mp4
DolbyVision/SD/Patterns_Of_Nature_HLG-P8.4_SD_24_H265-1Mbps_DD+JOC-768Kbps.mp4
CodecContainerMatrix/AV1/av1-aom-allintra-8bit.mp4
CodecContainerMatrix/H264/h264-ffmpeg-h264-tta.mkv
CodecContainerMatrix/MPEG4-Part2/mpeg4-part2-ffmpeg-mushishi24-head.mkv
```

复制保持相对路径，不转码、不 remux、不修改时间戳语义；源和副本逐文件计算 SHA-256。`remote-staging-manifest.json` 同时记录源路径、副本路径、大小、hash、SMB share 路径和服务拓扑。每轮结束可删除 staging 副本，但持久证据目录和 manifest 保留。若 Local 与 SMB 实际对象 hash 不同，`REMOTE-IDENTITY-01` 失败。

WebDAV 不接受 staging 写入。首次盘点夸克只读目录时生成 `webdav-fixture-registry.json`，记录每个采用对象的稳定路径、大小、SHA-256、`ffprobe` 媒体事实、许可边界和预期能力；后续运行只读核对并播放，不上传、重命名或删除远端内容。WebDAV registry 需要覆盖与 Local/SMB 相同的播放能力类别，但不伪造跨来源文件身份。

P2 在磁盘与运行窗口允许时再加入 `HDR10/HDR10.MP4`、一个 HLG TS、一个 Panorama 和一个 3D 文件；大文件不应为了缩短测试而转码，因为那会改变被验证对象。

## 失败分类

`result.json` 必须记录第一处失败步骤和以下唯一主分类；可以附加次分类，但不能以“flaky”代替定位。

| 分类 | 定义 | 处理边界 |
|---|---|---|
| `product-ui` / `product-control` | 元素存在但真实点击无效、状态错误、错误控件可用性 | 产品缺陷；保留前后截图与 AX tree |
| `product-source` / `product-remote` / `product-library` | 引用、授权、目录、认证、Range、持久化或来源生命周期违反合同 | 产品缺陷；同时保留 App 与服务器日志 |
| `product-playback` / `product-track` / `product-presentation` | PlaybackCore/Adapter、轨道、timeline、consumer 或 presentation 后置状态错误 | 按节点 01–09 报第一失败节点，不先改 UI 掩盖 |
| `product-error-ui` / `product-settings` / `product-policy` | 错误恢复、设置或产品策略与规格不符 | 产品缺陷 |
| `host` / `permission` / `system-panel` / `input` | Xcode/testmanagerd、TCC、Automation Mode、AX/CGEvent、系统面板或测试会话异常 | 基础设施失败；不算产品失败，也不能标绿 |
| `endpoint` / `network` / `credential` | AList/SMB 未启动、网络不可达、测试凭据或 Keychain 准备错误 | 环境失败；若 App 错误恢复也不合格，可同时记录产品失败 |
| `test-data` | 文件缺失、hash 漂移、registry/oracle 不完整、staging 不一致 | 数据失败；禁止换成另一个文件继续冒充同一用例 |
| `coverage-gap` | 新控件没有稳定定位或没有状态—动作条目 | 矩阵未完成；补测试性或条目后重跑 |

## 稳定重跑与完成定义

- 每条旅程从声明的前置状态开始；测试负责清理自己创建的 Library references、Keychain 测试凭据、保存来源和 staging，不依赖上一条旅程偶然留下的状态。
- 一次失败后的直接重试只用于采集诊断，不会把本轮转绿。修复或环境恢复后使用新 `run-id` 从预检重跑该层级；历史失败证据继续保留。
- P0 的 3 次连续运行使用同一 App bundle hash、媒体 hash 和端点配置，但每次采用全新 App 启动。P1 的第二次启动专门验证持久化，不复用仍存活的 Media Session。
- 每条播放用例至少断言：唯一 session、产品 FFmpeg route、首帧、后续帧、audio lane 事实、position 推进、无 terminal renderer error、操作后状态和 cleanup。机器 audio enqueue 不能改写成“物理可听且同步”。
- Computer Use 点击、XCUIAutomation、AX harness、server log、PlaybackCore snapshot 和视觉证据发生冲突时，本轮失败并保留全部事实，不选择最有利的证据。
- 完整 macOS E2E 只有在当前 revision 的 P0 与 P1 全部通过、P2 中本次变更相关切片通过、动作清单无 coverage gap、证据目录可重新审计时才可声明通过。它仍然不授予 Vision Pro L3 结论。
