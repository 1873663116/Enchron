# Enchron 已知问题

更新时间：2026-04-05

历史已解决问题见 `docs/archive/issues-archive/`。

---

## KI-013：MoltenVK 线程安全警告（非功能性）

### 优先级

低。不影响功能，属于 MoltenVK 已知行为。

### 现象

真机日志中反复出现 "Modifying properties of a view's layer off the main thread" 警告，来源于 `MVKSwapchain.initCAMetalLayer`。

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
