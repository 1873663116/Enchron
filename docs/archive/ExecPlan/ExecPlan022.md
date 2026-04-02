# ExecPlan 022 — T2.2 /qa E2E 端到端测试

**Round**: 13
**Pipeline State**: VERIFYING
**目标**: 在 Apple Vision Pro Simulator 上运行 /qa E2E 测试，覆盖三种播放模式

## 验证清单

### 窗口模式
- SDR/HDR10/DV 视频播放
- 控件交互（播放/暂停、进度条、音量）
- 音轨字幕切换

### 沉浸影院模式
- 虚拟屏幕渲染（平面 + 曲面）
- 平面/曲面切换（Settings）
- 位置调节（距离/高度/旋转）
- 3 个环境切换（暗黑影院/星空夜景/自然日落）
- 环境切换不中断播放

### 全景模式
- 360° 球体渲染
- 180° 半球裁剪
- 投影类型切换 Picker

### 通用
- 每个 UI 按钮功能验证（无空按钮/无占位）
- 播放模式自动路由验证
- Health Score ≥ 90

## 退出条件
- /qa 执行完成
- 结果记录到 overnight-log.md
- 发现 P0/P1 问题 → 回退 EXECUTING
- 无问题 → 继续 T2.4
