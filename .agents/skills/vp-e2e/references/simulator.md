# visionOS 模拟器 lane

本文的结论出自 2026-08-21 在 visionOS 27 模拟器上的实测，工具链为 Xcode 27 beta5（27A5237l）。
2026-08-25 又使用 Xcode 27 beta6（27A5252f）与 visionOS 27 Simulator（24M5357a）复核了构建、安装、启动和 `TestCommandChannel`；其余能力矩阵仍以原始实测为准。

模拟器的 App 容器就是 Mac 上的一个普通目录（路径由 `xcrun simctl get_app_container <设备> <bundle id> data` 给出）。因此，真机上所有依赖 `devicectl` 网络往返的通道，在模拟器 lane 全部退化为本地文件读写，没有拷贝延迟。

## 四条通道

### 产品状态：`TestCommandChannel`

以环境变量启动带测试通道的 App 进程：

```sh
SIMCTL_CHILD_ENCHRON_TEST_CHANNEL=1 \
  xcrun simctl launch --terminate-running-process <设备> com.xiongzhipeng.XrPlayer
```

这条通道的建立成本只有 App 冷启动的约 2 秒，不需要 XCTest、`xcodebuild` 或常驻 runner。实测 `ping` 往返 0.07 秒，跨轮询周期的动词约 0.5 秒。通道语义见[产品事实](product.md)。

### 合成输入：常驻 XCUITest runner

XCUITest 是 visionOS 上合成输入的标准通路，两条 lane 共用同一套机制。`interactive_visionpro_ui.py` 的 `--device` 参数收到模拟器 UDID 时会自行切换传输方式，命令形态与真机完全一致：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device <模拟器 UDID> --developer-dir "$(xcode-select -p)" \
  --derived-data-path .scratch/DerivedData-<主题> \
  --output-directory <证据目录> \
  ensure-session
```

传输层有三处差异：命令与应答文件由 `devicectl device copy` 改为直接读写容器目录；唤醒由 `devicectl device notification post` 改为 `simctl spawn notifyutil -p`；destination 改为 `platform=visionOS Simulator`。应答中 `devicectlCallCount` 为 0 即表示模拟器通路生效，`devicectl` 的 120 秒传输死锁问题随之消失。

两侧耗时在 `controller_timings.json` 中分开记账，模拟器的键带 `simulator:` 前缀。

打开本地媒体目前必须经真实点击完成。

### 空间手势：Device Hub 的鼠标映射

XCUITest 面对 Immersive Space 以及 RealityView 中的 TapGesture 与碰撞形状无能为力：它无法为空间表面推导激活坐标，合成点击也不携带注视加捏合语义。Device Hub 的 Vision Pro Simulator 画布补上了这个缺口。

Xcode 的 Device Hub 窗口中，Vision Pro Simulator 画布呈现佩戴者的第一人称视野，并把 Mac 的输入解释为空间输入：

- 鼠标指针在画布内悬停可产生 **Hover**，系统将它解释为 **Gaze**；
- 鼠标左键点击可产生 **OnTapGesture**，系统将它解释为 **Pinch**。

这条映射走系统真实的注视加捏合输入管线。它既覆盖普通 2D 窗口 UI，也能把 Pinch 与 Gaze 送达 Immersive Space 内的碰撞形状。Agent 可以通过合成 Mac 鼠标事件完成 Hover 与 On Tap Gesture，使空间手势验证在模拟器 lane 闭环。

该通路驱动 Mac 侧 GUI，不经 XCUITest 控制器。使用探针日志中的 `spatialTap` 与 `toggle` 事件判定动作是否送达产品。该能力仅适用于 Simulator 画布。真机的 Device Hub `View Screen` 在当前环境无法产生可用画面，详情见[真机 lane](device.md)。

### 系统控件与系统 Scene：仍由 Device Hub 驱动

Device Hub 默认窗口较小。开始定位前，先执行下方的 `enlarge` 流程，并把工具栏缩放挡位切到 fit。

Mac 合成鼠标事件可以点击 Device Hub 底部系统控制，包括等价于物理表冠按压的 Home 主菜单按钮、视角移动和 Tap Bar。画布内的权限对话框、Files 选择器、Photos 选择器、Home 主菜单与控制中心也可用同一通路操作。这些目标不需要出现在 App 的 Accessibility 树中。通过后继系统界面、App 收到的结果与产品证据确认动作到达。

编译计划遇到这些系统输入时，切换到 Device Hub 继续执行，不得以 XCUITest 无法触达为由标记 `blocked`。Simulator 仍不替代真机。Dolby Vision、AV1、MV-HEVC 第二视图与真实硬件音频输出继续使用 device lane。

Files 选择器在 visionOS 中是独立系统窗口。2026-08-29 的现场实测表明，它首次打开时可能已经完成加载但仍位于 App 窗口之后，画面只表现为 App 被调暗、内容区空白。此时点击一次 Device Hub 工具栏的 Home 主菜单按钮，再点击一次返回，系统选择器会处于可操作的前景。随后依次选择 `On My Apple Vision Pro`、目标文件和 `Open`；不得把这个窗口层级状态误判为选择器未加载。Photos 选择器当前直接出现在前景，单击唯一视频资产后立即完成选择，不存在第二个确认按钮。

#### 操作这条通路

驱动它的是 `Scripts/verification/device_hub_canvas.py`。每次调用必须显式传入 `--device <Simulator UDID>`。脚本要求当前只有这一台 visionOS Simulator 处于 Booted 状态，并在结果的 `targetBinding` 中返回设备、运行时和设备名称；绑定不一致时拒绝发送输入。

**Device Hub 必须是前台应用，否则 cliclick 的事件落到别处，而且没有任何报错。** 这是这条通路最阴险的失败形态：命令返回成功、探针一行不增，读起来与「产品没收到点击」完全一致。从终端发命令本身不夺焦点，但任何 `osascript activate`、人手点一下终端、或别的应用弹窗都会。脚本因此在每一次指针动作前断言前台应用，不满足就拒绝执行而不是照发。

**画布有输入模式，默认那一档不是「交互」。** 画布底部工具栏的第二组有五个按钮：指针、平移、移动相机、环绕、缩放。停在「移动相机」时，鼠标点击被相机操作吞掉，应用侧一条探针都不增——命令全部返回成功，读起来与「碰撞体收不到点击」完全一致。切到第一个按钮（指针）之后，第一次点击就产生了 `spatialTap`。

**先把窗口拉大再瞄准。** 画布是等比缩放的，指点误差与画布尺寸成反比。实测把 Device Hub 窗口从 1306×809 拉到接近全屏 2297×1181，画布从 756×425 变成 1729×972，线性放大 2.29 倍，同一个目标的容错也随之放大同样倍数。顶栏按钮 60×60 app 点在 1280×720 播放窗上，画布小的时候只有约 12 个显示点，拉大之后约 27 个——这是能不能点中的分界。脚本的 `enlarge` 子命令做这件事；画布已经达到 1200 点时它幂等返回，`gaze`/`pinch` 在画布宽度不足 1200 点时直接拒绝。

**拉大窗口只是一半，另一半是把工具栏的缩放挡位切到 fit。** 缩放停在 1:1 时，画布保持自己的尺寸不随窗口长大，窗口 2297 点宽而画布只有 850 点。此时 `canvas_rect` 的色块分割量到的是一条贯穿整个窗格的细带，宽高比自检报出 21.57 并拒绝执行——拒绝是对的，但光看这条报错不知道该动哪里，因此三条守卫的措辞都点名了缩放挡位。同一个窗口切到 fit 之后画布是 1729×972。

这一个挡位改变了一条判定。2026-08-26 上一轮把 J07 顶栏齿轮记为「点出碰撞体命中而非按钮激活」，当时画布正停在 1:1。在 fit 画布上重跑同一次点击，Video Format 面板正常打开，`spatialTap` 计数纹丝不动——说明这一下根本没落到碰撞体上。排除带 `topFraction=0.11111111` 是对的，齿轮整个落在带内，上一轮那个结果是瞄偏，不是产品缺陷。

**画布渲染的就是 `simctl io screenshot` 的那一帧，因此坐标映射是纯粹的缩放加平移，没有透视项。** 一度以为需要为第一人称透视建模，是因为把画布矩形量错了。量准的判据是画布宽高比必须等于模拟器截图的 16:9：脚本按窗口内「与 chrome 主色差异显著」的最长连续行段与列段定位画布，再用宽高比自检，实测 1.7788 对 1.7778，偏差 0.06%；比值对不上就报错，宁可不动手也不基于错误的量测去瞄。

**Device Hub 的 Accessibility 层级只公开通用按钮。** 2026-08-29 使用 Orca 读取到窗口标题 `Apple Vision Pro – visionOS 27.0`、十个无标签按钮和窗口控件；该层级不能区分 Pointer、Home 或视角按钮。窗口矩形仍取自 `CGWindowList`（`device_hub_window.swift`，owner 名是带空格的 `Device Hub`），工具栏语义由像素字形位置和结构不变量确定。移动与缩放使用分步合成拖拽；一次性 `dd`→`du` 会因窗口跟不上而少走一截。

常驻 UI 测试开始录屏后，Device Hub 工具栏会把原来的录制按钮展开为计时与停止两个元素，按钮总数由 10 变为 11。Home 始终是第一个元素，Pointer 始终是从末尾倒数第七个元素；驱动器按这两个结构位置定位，而不是写死一个会随录屏状态漂移的绝对索引。

### 取证

`xcrun simctl io <设备> screenshot <路径>` 捕获佩戴者视角下的整个模拟房间及其中所有 Scene，覆盖面大于 XCUITest 的 application 元素截图，且不需要建立会话。输出路径必须写入 `TMPDIR`：写入仓库内路径会被拒绝为 `Operation not permitted`。

XCUITest 截图在本 lane 返回真实像素，尺寸为当前 application 元素大小（主窗口 1536×864，播放窗口 1280×720）；真机上偶发的 1×1 退化在模拟器上不出现。

`tmp/playbackcore-live-debug/current.json`、`Documents/surface-tap-probe.log` 与 `TestCommandChannel` 的 `probeStatus` 都是容器内文件，直接读取即可。诊断串仍然只有 Accessibility value 一条出口，读取它需要 XCUITest 会话。

XcodeBuildMCP 的 UI 自动化已被证伪：`snapshot_ui` 报 SUCCEEDED 而 `targets` 为空数组；`wait_for_ui` 对确实存在于 XCUITest 层级中的 identifier 一律超时；而所有输入动词都要求先从快照取得 elementRef，因此整条输入链路不可用。同一工具的 `screenshot` 正常。

## 能力边界

### 视频解码

解码由 `AVSampleBufferVideoRenderer` 内部的 VideoToolbox 完成，两条 lane 的能力差异集中于此。

下表的轴取自 `PlaybackFFmpegBridge.c` 的 `codec_type()`——它是决定何种编码可以递交渲染器的唯一位置，映射为 0 的编码无法通过 `compressed_codec_is_renderable`。产品的视频编码面即以下五族。

| 编码 | 模拟器 | 真机 |
| --- | --- | --- |
| H.264 | 有 | 有 |
| HEVC | 有 | 有 |
| Dolby Vision HEVC | **无** | 有 |
| AV1 | **无** | 有（M5 硬解） |
| ProRes 六种 | 无 | 无 |

MV-HEVC 是 `hvc1` 加多层结构，不是独立编码。模拟器可以解出基础层并输出正常尺寸的 pixel buffer，但 `kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs` 返回 `kVTPropertyNotSupportedErr`（−12900），解码回调也不携带 `CMTaggedBufferGroup`，因此空间视频在模拟器上只有单眼画面。

`videoDecoderMatrixIsRecorded`（`Tests/EnchronApp/VideoDecoderAvailabilityTests.swift`）在任一侧执行一次，就会把该侧对应列写入容器的 `video-decoder-matrix.tsv`。上表的模拟器列由它产出，真机列待其复核。

### 音频解码

FFmpeg 桥自行解码音频并产出 `kAudioFormatLinearPCM`（`Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c`），递交渲染器的已经是 LPCM，不经过系统音频解码器。因此音轨相关的结论在两条 lane 完全等价。

### 感知硬件

ARKit 会话在模拟器上无法建立，运行日志给出 `Hand Tracking is enabled but not supported on this device`。手部骨骼追踪、世界感知与真实的注视加捏合硬件在模拟器上都不存在（Device Hub 的鼠标映射是系统提供的输入替代，不依赖这些硬件）。`xcrun simctl privacy` 只覆盖 iOS 一族的服务，没有手部结构或周围环境的条目。

### 签名与 Keychain

以 `CODE_SIGNING_ALLOWED=NO` 构建的 App 只有 linker 签名、不携带任何 entitlements，`SecItemAdd` 会返回 `errSecMissingEntitlement`（−34018），凭据保存全部失败。默认 `xcodebuild` 的 Sign to Run Locally ad-hoc 签名携带正确身份，Keychain 正常。注意 `Scripts/test-visionos-domain.sh` 采用前一种构建方式，而 `EnchronDomainTests` 的 TEST_HOST 是 Enchron.app，因此该脚本执行完毕会在模拟器上留下一份 Keychain 不可用的安装。手工验证 App 之前，先重装一份正常签名的构建。

## 已跑通的链路

**四种呈现在模拟器上均已跑通**：window、portal、panorama、docked。已证实的完整链路为：干净启动、`resetState`、导入媒体、自媒体库打开、window 播放出画出声、召唤与隐藏控件、打开 Video Format 面板、选择投影与立体布局、Apply 后 window 转 portal、portal 中继续播放、portal 转 panorama、panorama 全视野渲染、`exitSpatial` 退回 portal，以及 window 经 DockMenu 转 docked。

沉浸目标的判据与真机一致：进入沉浸后诊断串不可读，改看探针文件。

| 呈现 | 探针签名 | 截图应当看到 |
| --- | --- | --- |
| panorama | `rkContentType=equirectangular`，`wantImmersive` 与 `gotImmersive` 同为 `progressive`，`componentBound=true`，`surfaceOpacity=1.0` | 整个视野被视频填满，模拟房间消失 |
| docked | `rkContentType=mono`，`gotImmersive=none`，`componentBound=true` | 房间按所选明暗效果变暗或提亮，视频作为影院屏幕悬停于房间中 |

录屏通道同样成立，且覆盖面大于真机：以 `--test-plan Enchron` 建立会话，`halt` 使 XCTest 落盘，再由 `extract_visionpro_ui_recording.py` 提取。所得帧是佩戴者的整个视野而非仅 App 元素，转场、菜单开合与播放画面都在其中。真机上「录屏暂存写在头显侧、必须短会话」的约束在此不成立，但结果包仍然庞大（几十秒的会话约 65 MB），执行完毕照常清理。

## 尚未定性

沉浸往返是否会像真机那样逐渐导致合成事件停止投递，尚无结论。长会话中观察到过 runner 进程结束，该现象也可能源于外部进程管理。
