# Enchron 已知问题

更新时间：2026-03-26

已归档并标记为已解决：

- [known_issues_2026-03-06_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-06_resolved.md)
- [known_issues_2026-03-08_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-08_resolved.md)
- [known_issues_2026-03-10_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-10_resolved.md)

当前主文档只保留仍开放、且对当前产品判断有指导意义的问题。已在真机上确认关闭的问题，不再继续保留在这里。

2026-03-15 已确认关闭：

- KI-011：SMB 子目录浏览与子目录视频播放已修复。
- KI-007 的 `i` 信息面板容器与首次弹出问题已修复；该编号当前仅保留”首次构建后首启首播的一次性冷卡顿”子问题。

2026-03-26 已确认关闭：

- KI-010：CAEDRMetadata 已实现。`applyEDRMetadataToLayer()` 根据 HDR 类型自动设置（HDR10/HDR10+/DoVI→hdr10 metadata, HLG→hlg, SDR→nil）。`setHDREnabled()` 同步 edrMetadata。EDR metadata 选择逻辑有数据驱动单元测试覆盖。需真机验证视觉效果。

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
3. 如果后续要优化，重点应放在”能否把第一次真实 GPU 管线建链成本提前或平滑”，而不是继续在已经收缩过的普通播放逻辑上盲改。

---

## KI-012：全景视频投影类型自动检测未实现

### 优先级

中等。当前可通过手动切换播放模式使用全景功能。

### 现象

所有视频的 `projectionType` 被硬编码为 `.flat`（`MPVPlayerAdapter.swift` 第 1172 行）。全景视频（360°/180°/鱼眼）不会被自动识别并切换到全景模式。

### 根本原因

mpv 本身不通过 `video-params` 提供视频投影类型的元数据。需要通过其他策略检测：文件名模式匹配、视频宽高比（2:1 → 360°）、或读取 MP4 spherical metadata tag。

### 修正方向

1. 实现基于文件名和宽高比的启发式检测
2. 研究通过 FFmpeg/AVFoundation 读取 spherical metadata 的可行性
3. 在 `MediaProfile` 构建时注入检测结果

---

## KI-013：MoltenVK 线程安全警告（非功能性）

### 优先级

低。不影响功能，属于 MoltenVK 已知行为。

### 现象

真机日志中反复出现 “Modifying properties of a view's layer off the main thread” 警告，来源于 `MVKSwapchain.initCAMetalLayer`。

### 根本原因

MoltenVK 的 Vulkan swapchain 创建代码在非主线程操作 `CAMetalLayer` 属性。这是 MoltenVK 的已知行为，不会导致功能性问题，但会产生大量日志噪声。

---

## KI-014：饱和度增强需要自定义 RealityKit Compute Shader

### 优先级

中等。属于未来细节迭代。

### 现象

用户期望的饱和度增强不是简单的全局饱和度拉升（mpv `saturation` 属性），而是类似 YouTube 的选择性增强算法——只增强鲜艳颜色的饱和度，可能还涉及色相微调，场景中的中性色不变。

### 修正方向

1. 已移除 mpv `saturation` 属性调节路径
2. 未来需走统一 RealityKit 路径：在 PanoramaLayerBridge 的 Blit 之后插入 Metal Compute Shader
3. Shader 应实现：RGB→HSV 转换 → 基于饱和度阈值的选择性增强 → 可能的色相微调 → HSV→RGB 写回
4. Metal 4 的 `MTL4ComputeCommandEncoder` 可在同一 pass 中混合 blit 和 compute，简化管线
