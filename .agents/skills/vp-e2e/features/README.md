# Enchron 特性地图

本目录是仓库维护的验证真相源：每个用户可见特性一个文件，回答它是什么、用户怎么到达、harness 怎么驱动、什么可观察终态算证明。

## 自动化可达性承诺

Enchron 应用内的每项产品操作都由自动化到达，并由应用诊断串或探针证明事件已送达产品处理逻辑。Accessibility 层级中的存在性、`isHittable` 与 XCTest 动作返回值分别只证明目标被公开、框架报告可命中、框架完成调用，送达证据由应用给出。

承诺边界即 [SKILL.md](../SKILL.md) 的「人类验收」清单。清单之外的产品操作不可达即为缺陷，归属只有两类：产品公开的 Accessibility 事实不足，或测试通道缺少能进入同一产品状态与处理管线的动词。空间手势无法由 XCUIAutomation 合成时，DEBUG 动词进入同一产品状态或处理管线，并以应用证据完成送达判定。常驻透明机制窗口对 Accessibility 层级保持隐身，也不作为可命中目标。

全量操作集由 `Scripts/verification/generate_reachability_inventory.py` 自产品源码生成到 `Config/reachability_operation_inventory.json`，每个操作携带源码推导出的证明语境集合。浏览域操作在「主窗口浏览」语境证明一次；播放域操作按其生产渲染宿主实际出现的 Window、Portal、Panorama 或 Docked 语境逐项证明。同一控件在 ornament、attachment 或 dock 容器中复用时，各容器仍是独立的运行时判定点。生成器无法自生产宿主得到语境集合时失败，基线只收录真实判定点。

物理设备的第零层回归由 `Scripts/verification/reachability_matrix.py` 执行。已证明可达的判定点在被驱动后回退为不可达时，runner 失败。首次发现的不可达判定点保留为已知缺陷，直至修复并经真机复测转绿。

## 特性

**取得媒体**
- [media-import.md](media-import.md)：媒体进入资料库的路径。
- [remote-source-connection.md](remote-source-connection.md)：SMB 与 WebDAV 的添加、浏览与打开。
- [emby-library.md](emby-library.md)：Emby 的浏览、播放与服务器端观看状态。

**播放**
- [clean-state-playback.md](clean-state-playback.md)：干净状态下从媒体库打开并播放任意已入库视频。
- [picture-interpretation.md](picture-interpretation.md)：动态范围、立体、投影的正确解释。
- [track-selection.md](track-selection.md)：音轨与字幕轨的切换。
- [viewing-state.md](viewing-state.md)：观看进度与续播。
- [network-resilience.md](network-resilience.md)：网络抖动下的播放。

**呈现与界面**
- [mode-transitions.md](mode-transitions.md)：window、portal、docked、panorama 及其切换。
- [format-editing.md](format-editing.md)：Video Format 编辑（窗口菜单与面板 Advanced Settings 两个宿主）。
- [controls-summon.md](controls-summon.md)：播放控件的显示与隐藏。

**存储**
- [cache-and-artwork.md](cache-and-artwork.md)：容器索引缓存与 Artwork。

## 证据模型

每个文件的 `## 证据` 一节按三类证据列出该特性的要求与看守者：

| 种类 | 定义 | 产生者 |
|---|---|---|
| 结构 | 产品递出的内容在逻辑上正确 | 逻辑测试与源码级结构检查，秒级 |
| 物理 | 真机上采集到的客观数值正确 | 真机取证 |
| 感知 | 佩戴者的主观判断成立 | 佩戴者，每种情况一次；当时采集的帧成为参照物，此后由机器比对 |

**一条特性证实成功，等于它声明的证据集合齐备。** 分界规则是该断言的真假由谁决定：由产品自身代码决定的归结构证据，取决于 Apple 黑盒或物理世界的归物理证据，属于人的感受的归感知验收。

标注**待建**或**待做**的格子是当前无人看守之处，也是这份地图的主要用途。
