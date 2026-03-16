# Enchron 已知问题

更新时间：2026-03-17

已归档并标记为已解决：

- [known_issues_2026-03-06_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-06_resolved.md)
- [known_issues_2026-03-08_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-08_resolved.md)
- [known_issues_2026-03-10_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-10_resolved.md)

当前主文档只保留仍开放、且对当前产品判断有指导意义的问题。已在真机上确认关闭的问题，不再继续保留在这里。

2026-03-15 已确认关闭：

- KI-011：SMB 子目录浏览与子目录视频播放已修复。
- KI-007 的 `i` 信息面板容器与首次弹出问题已修复；该编号当前仅保留“首次构建后首启首播的一次性冷卡顿”子问题。

---

## KI-010：Window 模式 HDR 缺少 CAEDRMetadata，系统无法做精确 EDR tone mapping

### 优先级

当前最高优先级问题。

### 现象

- HDR10/HLG/DoVI 内容能被正确识别，UI 中的 HDR/SDR 信息能正确显示。
- libmpv gpu-next 路径已能正确渲染 HDR 内容（tone-mapping=auto + target-trc=auto）。
- Metal Layer 已配置为 rgba16Float + wantsExtendedDynamicRangeContent。
- 但显示效果仍不够精确——HDR 高光区域未被正确呈现。

### 调查结论（2026-03-17，修正 2026-03-15 的错误分析）

> **重要修正**：2026-03-15 的根因分析（根因 A~D）存在重大误判，已废止。当时把问题归因于 `verified_surface=false`、MoltenVK 线程违规、HDR surface 未建立等底层渲染路径问题。经过对 libmpv 渲染管线的重新调研，发现这些都不是真正的根因。

**真正的根因是：从未设置 `CAEDRMetadata`。**

libmpv gpu-next 路径内部已经正确完成了 HDR 渲染——它读取内容的 HDR 元数据，执行 tone mapping，将结果输出到 rgba16Float 的 Metal Layer。Metal Layer 也已经通过 `wantsExtendedDynamicRangeContent = true` 告知系统自己能承载 EDR 内容。

但是，Apple 显示系统需要通过 `CAEDRMetadata` 知道内容的 mastering 亮度范围（maxLuminance / minLuminance），才能做精确的 system-level EDR tone mapping。没有 CAEDRMetadata 时，系统只能以保守策略处理 EDR 内容，导致高光被压缩、亮度表现不准确。

### 根本原因

#### 唯一根因：MPVPlayerAdapter 未在 HDR 内容检测后设置 `layer.edrMetadata`

`applyHDRRuntimeConfiguration()` 中设置了 `wantsExtendedDynamicRangeContent = true`，但没有后续调用来设置 `CAEDRMetadata`。Apple 的 EDR 管线需要两个条件同时满足：

1. `wantsExtendedDynamicRangeContent = true` — 已满足
2. `layer.edrMetadata = CAEDRMetadata.hdr10(...)` 或 `.hlg(...)` — **缺失**

### 修正方向

1. 在 `applyHDRRuntimeConfiguration()` 中追加调用 `applyEDRMetadataToLayer()`，根据 HDR 类型设置对应的 CAEDRMetadata。
2. HDR10/HDR10+/DoVI：使用 `CAEDRMetadata.hdr10(minLuminance:maxLuminance:opticalOutputScale:)`，从 sig-peak 推算 maxLuminance（sig-peak * 203 nits），opticalOutputScale = 100.0。
3. HLG：使用 `CAEDRMetadata.hlg(ambientViewingEnvironment:)`。
4. SDR：设置 `edrMetadata = nil`。
5. `setHDREnabled(_:)` 中同步更新 edrMetadata（关闭时清除，开启时重设）。

### 关于之前的 `verified_surface` 和线程违规

这些日志信号仍然存在，但它们不是 HDR 显示效果不佳的根因。`verified_surface` 是 `MPVPlayerAdapter` 内部的验证逻辑，它反映的是内部状态模型的设计，而不是 Apple 显示系统是否收到了正确的 HDR 元数据。MoltenVK 的线程警告需要独立处理，但不阻塞 HDR 效果的修复。

---

## KI-007：首次构建后首启首播仍有一次性冷卡顿，但之后会进入秒切热态

### 现象

- 首次构建并安装成功后，第一次启动 App 再第一次点开视频时，仍然会有一次性明显卡顿和黑屏等待。
- 一旦第一次播放成功，之后同一轮使用中的切视频会进入非常快的热态，接近秒切。
- 这个问题不是每次启动都稳定复现，而是高度集中在“安装后的第一次真实播放”。
- 先前同条问题里包含的“i 面板容器与首次弹出卡顿”已经修正，不再属于当前开放问题。

### 调查结论（2026-03-15）

这条问题已经不能再笼统描述为“首播慢”。真机结果显示它更像是：**首次构建后，第一次真实进入 native GPU 播放路径时，会支付一次性的重型建链成本；一旦这条路径成功建立，之后就会进入热态。**

`i` 面板问题已关闭，真正剩下的开放点是“为什么 warmup 已完成，第一次真实播放仍然明显更慢”。

### 根本原因

#### 根因 A：warmup 只证明“基础预热完成”，不等于“真实播放渲染管线已经热好”

真机日志已经明确表明，用户点视频前就出现了：

- `warmup_requested`
- `warmup_waiting_for_layer`
- `warmup_started mode=native`
- `warmup_ready mode=native`

这说明 App 启动后确实会准备 player core。但这个准备到的状态，更接近“基础路径已建立，可以开始真正播放”，而不是“真实播放所需的渲染管线、shader cache、swapchain 和媒体链路都已经热好”。

#### 根因 B：第一次真实播放仍然承担了一次性的 GPU/VO 建链成本

第一次成功播放 HDR 内容时，真机日志会额外出现：

- MoltenVK 实例与设备创建
- swapchain image 创建
- `Spent 1010.191 ms generating shader LUT (slow!)`
- `Spent 1238.006 ms translating SPIR-V (slow!)`

这说明首次真正进入 `vo=gpu-next` 的 native GPU 播放路径时，仍在支付一次性的图形管线建立与 shader 编译成本。后续之所以秒切，就是因为这些昂贵步骤已经完成并处于热态。

#### 根因 C：当前“首启前状态”和“首次播放后状态”之间还没有被产品化地桥接起来

现在的 warmup 做到了“启动时先把 player core 拉起来”，但还没有做到“把第一次真实播放最贵的那部分成本也提前完成或平滑掉”。所以首次点播和后续切播看到的，其实不是同一种内部状态。

### 当前最可信的状态解释

#### App 启动但尚未点播时，播放核心是什么状态

根据现有日志，最可信的描述是：

- player core 已被创建；
- native 模式 warmup 已完成；
- 基础 layer 绑定前提已满足；
- 但尚未发生一次真正的 `vo=gpu-next` 播放；
- 因此真实播放所需的 shader LUT、SPIR-V 翻译、swapchain 热态和部分媒体链路缓存还没有建立。

#### 第一次成功播放后，播放核心是什么状态

根据现有真机现象，最可信的描述是：

- `mpv_ready` 与首次真实 `loadfile` 已走通；
- native GPU 播放路径已经成功建链一次；
- MoltenVK/libplacebo 相关的一次性初始化成本已支付；
- 后续切视频会复用这条已热起来的播放路径，因此体感接近秒切。

### 代码与真机证据

- `XrPlayer/XrPlayerApp.swift` 会在应用启动时调用 `player.warmup()`。
- 真机日志中 `warmup_ready` 出现在首次点击视频之前，说明“没有 warmup”不是当前根因。
- 真机日志中首次播放会出现 MoltenVK 创建、swapchain 创建、shader LUT 生成和 SPIR-V 翻译等重负载记录，说明真正的一次性成本发生在“第一次真实播放”而不是“App 刚启动”。

### 修正方向

1. 先不要再把这个问题笼统叫做“首播慢”，而要按“首次构建后首启首播的一次性冷建链成本”来调查。
2. 继续补足 warmup 前态与首次真实播放后热态之间的状态证据，回答“为什么只会一次”。
3. 如果后续要优化，重点应放在“能否把第一次真实 GPU 管线建链成本提前或平滑”，而不是继续在已经收缩过的普通播放逻辑上盲改。
