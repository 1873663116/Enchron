# Enchron 特性地图

本目录是仓库维护的验证真相源：每个用户可见特性一个文件，回答它是什么、用户怎么到达、harness 怎么驱动、什么可观察终态算证明。只验证了便捷入口而地图列有其它入口的证明是不完整的。

## 自动化可达性承诺

Enchron 应用内的每项产品操作都必须由自动化到达，并由应用诊断串或探针证明事件已经送达产品处理逻辑。Accessibility 层级中的存在性、`isHittable` 与 XCTest 动作返回值分别只证明目标被公开、框架报告可命中和框架完成调用；它们不能替代应用送达证据。

承诺边界是下列封闭清单：

- 系统域：权限对话框、Files 选择器的系统界面、Home、控制中心、系统窗口装饰把手；
- 物理输入：Digital Crown 的旋转与按压；
- 感知判断：舒适度、眩晕、音质以及其它必须由人类感官裁决的主观结论。

清单之外的产品操作不可达即为缺陷。缺陷归属只有两类：产品没有公开足够的 Accessibility 事实，或测试通道缺少能够进入同一产品状态与处理管线的动词。空间手势无法由 XCUIAutomation 合成时，DEBUG 动词必须进入同一产品状态或处理管线，并以应用证据完成送达判定。任何常驻透明机制窗口都不得向 Accessibility 层级暴露节点，也不得成为可命中目标。

全量操作集由 `Scripts/verification/generate_reachability_inventory.py` 从产品源码生成到 `Config/reachability_operation_inventory.json`。物理设备的第零层回归由 `Scripts/verification/reachability_matrix.py` 执行，覆盖 Window、Portal、Panorama 与 Docked；已证明可达的格回退为不可达时，runner 失败。首次发现的不可达格保留为已知缺陷，继续占据矩阵，直至修复和真机复测转绿。

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

每个文件有一节 `## 证据`，按三种证据列出这条特性要什么、谁在守：

| 种类 | 是什么 | 谁产生 |
|---|---|---|
| 结构 | 我们递出去的东西在逻辑上正确 | 逻辑测试与源码级结构检查，秒级 |
| 物理 | 真机上采集到的客观数值正确 | 真机取证 |
| 感知 | 人觉得对 | 佩戴者，每种情况一次；确认当时采集的帧成为参照物，此后由机器比对 |

**一条特性被证实成功，等于它声明的证据集合齐了。**声明了的缺一不可。分界规则是"这个断言的真假由谁决定"：由我们自己代码决定的进结构证据；取决于 Apple 黑盒或物理世界的进物理证据；是人的感受的进感知验收。

标着**待建**或**待做**的格子就是当前无人看守的地方，它们是这份地图的主要用途。
