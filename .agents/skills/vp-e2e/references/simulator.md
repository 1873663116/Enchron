# visionOS 模拟器 lane

结论出自 2026-08-21 在 visionOS 27 模拟器上的实测，工具链 Xcode 27 beta5（27A5237l）。

模拟器的 App 容器即 Mac 上的普通目录（`xcrun simctl get_app_container <设备> <bundle id> data`），真机上依赖 `devicectl` 往返的通道在此均为本地文件读写。

## 三条通道

### 产品状态：`TestCommandChannel`

```sh
SIMCTL_CHILD_ENCHRON_TEST_CHANNEL=1 \
  xcrun simctl launch --terminate-running-process <设备> com.xiongzhipeng.XrPlayer
```

建立成本为 App 冷启动约 2 秒，无需 XCTest、`xcodebuild` 或常驻 runner。实测 `ping` 往返 0.07 秒，跨轮询周期的动词 0.5 秒。通道语义见 [产品事实](product.md)。

### 真实输入：常驻 XCUITest runner

合成输入在 visionOS 上仅有 XCUITest 一条通路，两条 lane 机制相同。`interactive_visionpro_ui.py` 的 `--device` 收到模拟器 UDID 时自行切换传输，命令形态与真机一致：

```sh
python3 Scripts/verification/interactive_visionpro_ui.py \
  --device <模拟器 UDID> --developer-dir "$(xcode-select -p)" \
  --derived-data-path .scratch/DerivedData-<主题> \
  --output-directory <证据目录> \
  ensure-session
```

传输层的三处差异：命令与应答文件由 `devicectl device copy` 改为直接读写容器目录，唤醒由 `devicectl device notification post` 改为 `simctl spawn notifyutil -p`，destination 改为 `platform=visionOS Simulator`。应答中 `devicectlCallCount` 为 0 即该通路生效，`devicectl` 的 120 秒传输死锁随之消失。

| 环节 | 模拟器 | 真机 |
| --- | --- | --- |
| `ensure-session` | 24.3 秒 | 25.7 秒，可能撞上佩戴者授权门槛 |
| `snapshot` 往返 | 0.2 到 0.9 秒 | 2.3 到 2.5 秒 |

两侧耗时在 `controller_timings.json` 中分开记账，模拟器的键带 `simulator:` 前缀。

模拟器不存在佩戴者授权 Scene，`Timed out while enabling automation mode.` 一族分流在本 lane 不适用。

打开本地媒体目前必须经真实点击。

### 取证

`xcrun simctl io <设备> screenshot <路径>` 捕获佩戴者视角下的整个模拟房间及其中所有 Scene，覆盖面大于 XCUITest 的 application 元素截图，且不需要会话。输出路径写入 `TMPDIR`，仓库内路径将被拒绝为 `Operation not permitted`。

XCUITest 截图在本 lane 返回真实像素，尺寸为当前 application 元素大小（主窗口 1536×864，播放窗口 1280×720），真机的 1×1 退化不出现。

`tmp/playbackcore-live-debug/current.json`、`Documents/surface-tap-probe.log` 与 `TestCommandChannel` 的 `probeStatus` 均为容器内文件，直接读取，无拷贝延迟。诊断串仍仅有 Accessibility value 一条出口，需要 XCUITest 会话。

XcodeBuildMCP 的 UI 自动化已证伪：`snapshot_ui` 报 SUCCEEDED 而 `targets` 为空数组，`wait_for_ui` 对确实存在于 XCUITest 层级中的 identifier 一律超时，而所有输入动词均要求先自快照取得 elementRef。同一工具的 `screenshot` 正常。

## 能力边界

### 视频解码

解码由 `AVSampleBufferVideoRenderer` 内部的 VideoToolbox 完成，两条 lane 的差异集中于此。

轴取自 `PlaybackFFmpegBridge.c` 的 `codec_type()`，它是决定何种编码可递交渲染器的唯一位置，映射为 0 的编码无法通过 `compressed_codec_is_renderable`。产品的视频编码面即以下五族。

| 编码 | 模拟器 | 真机 |
| --- | --- | --- |
| H.264 | 有 | 有 |
| HEVC | 有 | 有 |
| Dolby Vision HEVC | **无** | 有 |
| AV1 | **无** | 有（M5 硬解） |
| ProRes 六种 | 无 | 无 |

MV-HEVC 是 `hvc1` 加多层结构而非独立编码。模拟器可解出基础层并输出正常尺寸的 pixel buffer，而 `kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs` 返回 `kVTPropertyNotSupportedErr`（−12900），解码回调亦不携带 `CMTaggedBufferGroup`，故空间视频在模拟器上仅有单眼。

`videoDecoderMatrixIsRecorded`（`Tests/EnchronApp/VideoDecoderAvailabilityTests.swift`）在任一侧执行一次即将该侧对应列写入容器的 `video-decoder-matrix.tsv`。上表模拟器列由它产出，真机列待其复核。

### 音频解码

FFmpeg 桥自行解码音频并产出 `kAudioFormatLinearPCM`（`Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c`），递交渲染器的已是 LPCM，不经系统音频解码器。音轨相关结论在两条 lane 等价。

### 感知硬件

ARKit 会话在模拟器上无法建立，运行日志给出 `Hand Tracking is enabled but not supported on this device`。手部追踪、世界感知与真实注视加捏合均不存在。`xcrun simctl privacy` 仅覆盖 iOS 一族的服务，无手部结构或周围环境条目。

### 签名与 Keychain

以 `CODE_SIGNING_ALLOWED=NO` 构建的 App 仅有 linker 签名、不携带任何 entitlements，`SecItemAdd` 返回 `errSecMissingEntitlement`（−34018），凭据保存全部失败。默认 `xcodebuild` 的 Sign to Run Locally ad-hoc 签名携带正确身份，Keychain 正常。`Scripts/test-visionos-domain.sh` 采用前一种构建，而 `EnchronDomainTests` 的 TEST_HOST 为 Enchron.app，因此该 lane 执行完毕会在模拟器上留下一份 Keychain 不可用的安装。手工验证 App 之前重装一份正常签名的构建。

## 已跑通的链路

**四种呈现在模拟器上均已跑通**：window、portal、panorama、docked。已证实的完整链路为干净启动、`resetState`、导入媒体、自媒体库打开、window 播放出画出声、召唤与隐藏控件、打开 Video Format 面板、选择投影与立体布局、Apply 后 window 转 portal、portal 中继续播放、portal 转 panorama、panorama 全视野渲染、`exitSpatial` 退回 portal，以及 window 经 DockMenu 转 docked。

沉浸目标的判据与真机一致：进入后诊断串不可读，改看探针文件。

| 呈现 | 探针签名 | 截图应当看到 |
| --- | --- | --- |
| panorama | `rkContentType=equirectangular`，`wantImmersive` 与 `gotImmersive` 同为 `progressive`，`componentBound=true`，`surfaceOpacity=1.0` | 整个视野被视频填满，模拟房间消失 |
| docked | `rkContentType=mono`，`gotImmersive=none`，`componentBound=true` | 房间按所选明暗效果变暗或提亮，视频作为影院屏幕悬停于房间中 |

录屏通道同样成立且覆盖面大于真机：以 `--test-plan Enchron` 建立会话、`halt` 使 XCTest 落盘，再由 `extract_visionpro_ui_recording.py` 取回，所得帧为佩戴者的整个视野而非仅 App 元素，转场、菜单开合与播放画面均在其中。真机上「录屏暂存写在头显侧、必须短会话」的约束在此不成立，结果包仍然庞大（几十秒会话约 65 MB），执行完毕照常清理。

## 尚未定性

沉浸往返是否如真机那样逐渐导致合成事件停止投递。长会话中观察到过 runner 进程结束，该现象亦可能源于外部进程管理。
