---
name: verify-enchron
description: 无人化验证 Enchron visionOS 产品 App 的用户路径：干净状态播放、格式编辑、呈现切换、控件召唤。驱动物理 Vision Pro，不需要任何人手点击。设备机制与故障分流归 visionpro-xcuitest skill，本 skill 只负责 App 级验证流程。
---

# Verify Enchron

在物理 Vision Pro 上以真实用户路径验证 Enchron。所有底层设备事实（会话生命周期、观测通道有效范围、已证伪路径、佩戴者边界）以 `visionpro-xcuitest` skill 及其 `references/enchron.md` 为权威，先读它们再用本文件；本文件不重复那些内容，只提供 App 级验证的可执行流程。

## Launch

构建一次，之后所有会话复用产物：

```sh
DEVELOPER_DIR=/Volumes/Cortisol/Applications/Xcode-beta3.app/Contents/Developer \
xcodebuild build-for-testing -project Enchron.xcodeproj -scheme Enchron \
  -testPlan Enchron -destination "platform=visionOS,id=00008142-001871A11491401C" \
  -derivedDataPath /Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData \
  -clonedSourcePackagesDirPath /Volumes/Cortisol/DevSpace/Xcode/Enchron/ClonedPackages
```

会话建立与就绪判定用控制器的 `ensure-session`（`stage: ready` 才算成立）。常驻 runner 以 `ENCHRON_TEST_CHANNEL=1` 启动 App，App 内测试命令通道随之可用。

## Doctor

任何异样先跑这三条只读检查，全部通过才值得继续驱动：

1. `ensure-session` 返回 `stage: ready` 且给出新 sessionID。
2. `app-command --verb ping` 返回 `ok: true`（通道活性；它走文件轮询，即使窗口场景输入已死也应答——因此 ping 通过而 tap 无探针投递，就是输入所有权死亡的确诊，处置见 visionpro-xcuitest 的边界一节）。
3. 探针文件可取回（`devicectl device copy from … Documents/surface-tap-probe.log`）。

## Drive

统一入口是矩阵 runner，路径即数据：

```sh
python3 Scripts/verification/playback_mode_matrix.py --list-paths
python3 Scripts/verification/playback_mode_matrix.py \
  --clean --paths clean-open --reps 1 \
  --clips "Spatial/Stereo180/180_3D.mp4" \
  --evidence-dir <evidence>/run-<stamp>
```

`--clean` 使每个 cell 从定义好的干净状态出发（resetState → 重启加载空库 → 推送 → 生产管线导入 → 单片源库校验）。单片源库同时是结构性防线：自动连播无处可去，被禁片源永不可达。

手工驱动的三条铁律（都付过学费）：
- 窗口 chrome 秒级自动隐藏：任何 chrome 点击序列先点 `PlayerUI-window-playback-surface` 唤出并紧凑连发；格式菜单一旦打开会钉住可见性。
- 空间捏合无法合成：settled panorama 的入场元素只有 `PlayerUI-immersive-playback-surface`，对它 tap 会报成功但不投递（详见 visionpro-xcuitest 已证伪路径）。
- 不要在控制器外再包 shell 循环；批量序列写进矩阵 runner 或独立脚本。

App 级测试命令通道动词：`ping`、`toggleControls`、`resetState`、`importMedia`（配合 TestMediaInbox 推送）、`listLibrary`。

## Evidence

- 逐 cell 权威记录：`results.jsonl`（verdict、landed、时序、探针摘录路径）。
- 时间线：探针文件（打开链路 libraryTap→libraryOnPlayReturned、settle 判据分解、controlsWindow open/dismiss、testcmd 记录、modeRequestRetry 事件）。
- 状态快照：窗口态读 `PlayerUI-window-control-plane` 诊断串；沉浸态只信探针。
- 像素：默认 `--no-screenshot`；确需目视时先核对片源许可（TestMedia 部分 180° 源为成人内容，HNVR 名下文件绝对禁开）。
- 证明标准：走真实用户路径（库点击、chrome 点击、生产导入管线）；通道动词只用于真实输入物理不可合成（捏合召唤）或非产品行为（状态重置、注入）之处。

## Cleanup

`halt`（作用域限本 checkout，返回 terminated/remaining，remaining 空才算干净）。证据目录不属于清理对象，永远保留。设备上的 TestMediaInbox 与探针日志是低成本常驻，不必清。

## Helpers

- `Scripts/verification/playback_mode_matrix.py`：矩阵 runner（上文用法）。
- `Scripts/verification/interactive_visionpro_ui.py`：控制器（`--help` 为准）。
- 特性地图见 `features/README.md`，逐特性的驱动与证据判据在各自文件。
