# visionOS 模拟器 lane

本文的结论出自 2026-08-21 在 visionOS 27 模拟器上的实测，工具链为 Xcode 27 beta5（27A5237l）。
2026-08-25 又使用 Xcode 27 beta6（27A5252f）与 visionOS 27 Simulator（24M5357a）复核了构建、安装、启动和 `TestCommandChannel`；其余能力矩阵仍以原始实测为准。
2026-09-10 工具链换到 Xcode 27.0 正式版（27A266a）与 visionOS 27 Simulator 正式版 runtime（24M362），复核了构建、安装、启动与 `TestCommandChannel` ping；其余能力矩阵仍以原始实测为准。24M362 只接受 `com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K` 设备类型，对 2732x2048 的 `Apple-Vision-Pro` 返回 `Incompatible device`（SimError 403）。

模拟器的 App 容器就是 Mac 上的一个普通目录（路径由 `xcrun simctl get_app_container <设备> <bundle id> data` 给出）。因此，真机上所有依赖 `devicectl` 网络往返的通道，在模拟器 lane 全部退化为本地文件读写，没有拷贝延迟。

## 四条通道

### 产品状态：`TestCommandChannel`

以环境变量启动带测试通道的 App 进程：

```sh
SIMCTL_CHILD_ENCHRON_TEST_CHANNEL=1 \
  xcrun simctl launch --terminate-running-process <设备> com.xiongzhipeng.Enchron
```

这条通道的建立成本只有 App 冷启动的约 2 秒，不需要 XCTest、`xcodebuild` 或常驻 runner。实测 `ping` 往返 0.07 秒，跨轮询周期的动词约 0.5 秒。通道语义见[产品事实](product.md)。

### 合成输入：常驻 XCUITest runner

XCUITest 是 visionOS 上合成输入的标准通路，两条 lane 共用同一套机制。`transport.py` 的 `--device` 参数收到模拟器 UDID 时会自行切换传输方式，命令形态与真机完全一致：

```sh
python3 Scripts/console/transport.py \
  --device <模拟器 UDID> --developer-dir "$(xcode-select -p)" \
  --execution-input <证据目录>/execution-input.json \
  --output-directory <证据目录> \
  ensure-session
```

传输层有三处差异：命令与应答文件由 `devicectl device copy` 改为直接读写容器目录；唤醒由 `devicectl device notification post` 改为 `simctl spawn notifyutil -p`；destination 改为 `platform=visionOS Simulator`。应答中 `devicectlCallCount` 为 0 即表示模拟器通路生效，`devicectl` 的 120 秒传输死锁问题随之消失。

两侧耗时在 `controller_timings.json` 中分开记账，模拟器的键带 `simulator:` 前缀。

打开本地媒体目前必须经真实点击完成。

### 空间手势：Device Hub 的鼠标映射

XCUITest 无法合成画布上的缩放与捏合映射，也无法为 Immersive Space 与 RealityView 的空间表面推导激活坐标。这类端到端操作走 Device Hub：画布呈现佩戴者视野，把人手在 Mac 上的鼠标位置与点击映射成系统的注视与捏合，computer use 在画布上合成鼠标事件，代替缩放与捏合的点击。开始前放大 Device Hub 窗口，把画布缩放挡位切到 fit、输入模式切到指针；画布越大，指点越准。

同一通路到达不在 App Accessibility 树里的系统目标：Files 选择器、Home 主菜单、控制中心。点击前后各用 `xcrun simctl io <设备> screenshot` 取一张画面，再用后继系统界面与产品证据确认动作到达。普通 2D 窗口的点击也可这样完成，界面元素仍直接读 App 的 Accessibility 树。

需要这类动作的场景在控制台目录里登记为跳过（`Config/console/skipped-scenarios.json`），不生成端到端单元；端到端确认由 Agent 在 Device Hub 上按上面的方式执行。

Simulator 不替代真机。Dolby Vision、AV1、MV-HEVC 第二视图与真实硬件音频输出继续使用 device lane。


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

录屏通道同样成立，且覆盖面大于真机：`transport.py` 不接受 `--test-plan` 参数，需先以 `Enchron` 测试计划（`preferredScreenCaptureFormat: screenRecording`）`build-for-testing` 出 xctestrun 并冻结出指向它的执行输入，用这份执行输入建立会话，`halt` 使 XCTest 落盘，再由 `extract_visionpro_ui_recording.py` 提取。所得帧是佩戴者的整个视野而非仅 App 元素，转场、菜单开合与播放画面都在其中。真机上「录屏暂存写在头显侧、必须短会话」的约束在此不成立，但结果包仍然庞大（几十秒的会话约 65 MB），执行完毕照常清理。

## 尚未定性

沉浸往返是否会像真机那样逐渐导致合成事件停止投递，尚无结论。长会话中观察到过 runner 进程结束，该现象也可能源于外部进程管理。
