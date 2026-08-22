---
name: vp-e2e
description: 适用于根据运行时现场进行端到端调试、读取 App 公开的诊断状态与 Accessibility 层级、埋设备内探针、截图和录屏。
---



# Vision Pro 端到端调试与回归

开始前，先阅读 UI 测试目录内最近的指引，并检查当前 runner、控制器、录屏提取器及其 `--help` 输出。Bundle ID、命令、destination 和证据位置由项目内当前文件负责。

 [references/product.md] 是与 lane 无关的驱动与取证事实：三条状态通道、元素命中陷阱、identifier 在系统容器里的存活规则、矩阵与扫描的用法。两条 lane 都适用。
 [references/simulator.md] 与 [references/device.md] 分别是两条 lane 的通道、代价与各自独有的坑。
 [features/README.md] 是 Enchron 的特性地图：每个用户可见特性一个文件，说明它是什么、用户怎么到达、什么终态算证明。只验证了便捷入口而地图列有其它入口的证明是不完整的。
 [references/operation-units.md] 是回归集：产品的全部操作按操作单元分组，逐条给出驱动方式与判据。它由 `Scripts/verification/journey_units.py reference` 生成，不手工编辑。
 [references/journeys/index.md] 是回归轮次的组织层：13 条旅程（常备 10 条，J00/J05/J06 按需），由 `Scripts/verification/regression_journeys.py reference` 生成，不手工编辑。开轮先 `regression_journeys.py run open` 建台账，每条旅程读完判据即 `run verdict` 记录，收轮 `run close`；台账未收前，Stop hook 会拒绝结束回合，显式放弃用 `run abort --reason`。
 播放 PASS 必须有像素佐证。


## lane

E2E测试默认在模拟器上，除以下内容进行真机测试：
- Dolby Vision 与 AV1 编码格式播放画面。模拟器没有这两个解码器。
- 双层 MV-HEVC 的第二视图。模拟器只解基础层，立体对不产生。

二者共用常驻 XCUITest runner 与控制器，`--device` 收到模拟器 UDID 时控制器自行切换传输，命令形态不变。回归 runner 目标：`ENCHRON_TARGET_DEVICE` 设成模拟器 UDID 就把整轮矩阵移到模拟器 lane（`Scripts/verification/enchron_target.py`）。

根据情况灵活判断：大部分调试和debug可在模拟器完成，真机可以作为额外取证层或二次验收点。


## 人类验收

以下内容 Agent 无法测试，除此之外不必征询：
- 手部追踪，以及空间表面上的注视加捏合。XCUIAutomation 无法为空间表面推导激活坐标，合成点击也不携带注视加捏合语义（见 [产品事实](references/product.md) 的通道有效范围）。
- 物理输入：Digital Crown 的旋转与按压。
- XCTest 触达不到的系统 Scene：权限对话框、Files 选择器的系统界面、Home、控制中心等。
- HDR亮度、画面舒适度、眩晕，音质。

投影与立体布局不在其中。mono、SBS、TB 在 2D 截图就各自不同，结合结构化字段就可以判断输出是否正确。


## 测试

bug复现，回归测试模拟真实用户操作；非特殊情况默认不使用 hack 手段。
导入媒体、开始播放、切换呈现模式、读诊断状态与层级、取回探针、截图录屏，由控制器连续完成。

**操作单元**是一次驱动中的整块动作。它通常不是单步，例如：`library.new-folder` 打开管理菜单、点新建、输入名称、确认，再检查网格上出现该文件夹，共一次调用、一个判据、数秒完成。

单元之间的先后由各自的 `needs` 决定，不是文件顺序。前置单元失败时，依赖它的单元不产生信息，跳过并记为阻塞，不要当作通过。

每步声明驱动方式：
- `real` 走产品自己的 hit testing 与手势识别，是唯一能证明"用户能操作到"的方式。
- `injected` 绕过了这条路径的一部分，须写明绕过了什么、因此对哪一类缺陷失明。
- `setup` 与 `evidence` 自身不证明任何操作。
- `wearer` 需要佩戴者在头显里。

同一控件在 window 与 panorama 不重叠，因为那是对两个宿主的两次 hit test，一个通过不能替另一个作证。

另外两条回归通道回答别的问题，不能互相替代：
- `Scripts/verification/reachability_matrix.py` 是物理可达性基线。单元问产品做对了没有，基线问操作送不送得到。它与操作单元共用同一份源码派生清单作为轴。
- `Scripts/verification/playback_mode_matrix.py` 是播放模式矩阵，轴是片源 × 呈现路径，回答某种媒体在某条路径上放不放得出来。它与操作无关。
