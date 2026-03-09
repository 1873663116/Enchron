# Enchron 质量门禁

> 纯粹的验收清单——**怎样才算过关**。
> 不解释"为什么"，设计哲学见 `product_philosophy.md`；优先级排序见 `AGENTS.md`。

---

## 一级门禁：产品体验

### G1. Apple 原生风格优先
- 容器、列表、过渡、材质、排版应优先复用系统方案
- 自定义组件或动画需有明确理由，且不破坏系统一致性

### G2. 二级进度条不可退化
- 进入路径清晰
- 时间轴逻辑可理解
- 关键操作可精准命中
- 不可因新改动让它变慢、变乱或更难用

### G3. 播放控件必须"看得见、选得准、能确认"
- 重要按钮不可视觉消失
- 重要控件不可缺少 hover / focus / active 反馈
- gaze 命中区域须满足 visionOS 开发规范

---

## 二级门禁：性能与感知流畅度

### G4. 冷启动首播必须可被测量
对本地播放和远程播放，至少能区分以下阶段：
- 播放请求发起 → layer ready → player ready → remote ready → 首帧可见

缺少阶段日志，就无法判断瓶颈出在哪一层。

### G5. 不接受明显可感知的卡顿
以下情形应视为体验缺陷：
- 动效发木
- 时间轴拖动跟手性差
- 播放控制出现掉帧感
- 切换模式时肉眼可见卡顿

### G6. 新增动效须服从主链路流畅度
- 装饰性动效不可拖慢播放或控件响应
- 性能与装饰冲突时，优先性能

---

## 三级门禁：HDR 可信度

### G7. HDR 识别必须稳定
- HDR10 / HDR10+ / Dolby Vision / HLG / SDR 的识别路径应可解释
- UI 标签须可信，不可随意显示

### G8. HDR / SDR 切换开关必须可验证
- HDR 内容播放时，切换按钮行为应明确
- SDR 内容播放时，不应出现误导性 HDR 控件
- 切换后至少有一条可验证证据：状态、日志或测试

### G9. 映射正确性优先于"先跑起来"
- 颜色偏差、高光被压坏、错误色彩空间均属高优先级缺陷
- 不可因临时 workaround 牺牲映射正确性而不留证据

---

## 四级门禁：跨播放模式一致性

### G10. 控件行为跨模式一致
- 播放/暂停、快进快退、倍速、音轨/字幕切换等控件在三种播放模式下行为须一致
- UI 布局可因宿主环境不同而调整，但交互逻辑不可出现模式间差异

### G11. 接口设计须兼容沉浸场景
- PlaybackCore 的帧输出接口须同时支持 MTKView 直接渲染和 Metal 纹理桥接
- PlayerUI 的控件不可硬编码为窗口模式专属布局
- 播放模式决策逻辑须通过查询 SpatialScene 状态实现，不可在 PlayerUI 中硬编码

### G12. 新增功能不可破坏模块边界
- 不可绕过 protocol 接口直接引用其他模块的具体类
- Domain 层不可 import 框架或第三方库
- 跨模块数据传递须通过已定义的接口契约

---

## 五级门禁：工程与回归保护

### G13. 已知问题修复须留下回归资产
每修一个问题，至少补充其中之一：
- 自动化测试
- 更细的阶段日志
- 明确的 smoke 检查步骤

### G14. 核心体验问题不适合长期搁置
以下问题不应标记为"以后再说"：
- 核心控件反馈缺失
- 首播黑屏 / 冷启动体感差
- HDR 可信度问题
- 导致用户反复试错的交互缺陷

### G15. 实现不可默默偏离已拍板决策
任何实现若与 `product_philosophy.md` 或本文档冲突：
- 应先更新文档或说明例外
- 不可让偏离悄悄进入主线

---

## 六级门禁：编码级自动化守卫

### G16. SwiftLint 架构守卫

项目根目录的 `.swiftlint.yml` 包含两条自定义规则，在编译时自动执行：

| 规则 | 作用 | 级别 |
|------|------|------|
| `domain_no_ui_framework` | 所有模块 `Domain/` 下的文件禁止 import UIKit/SwiftUI/RealityKit/Metal/AMSMB2/ARKit | error |
| `no_force_try_in_domain` | 所有模块 `Domain/` 下的文件禁止 `try!` | error |

**Domain 层允许的例外 import**（以及理由）：
- `Foundation` — Swift 标准基础库
- `CoreVideo` — `CVPixelBuffer` 是视频帧的平台标准表示，避免在 Adapter 层做不必要的封装转换
- `Observation` — `@Observable` 宏是当前 Swift/SwiftUI 生态的实用选择，替代方案成本过高

**安装与使用**：
```bash
# 安装 SwiftLint
brew install swiftlint

# 手动检查
cd /Users/xiongzhipeng/Applications/Enchron
swiftlint lint
```

SwiftLint 已集成到 Xcode Build Phase，每次编译时自动运行。

### G17. WORKAROUND 注释规范

所有 `// WORKAROUND:` 注释必须在后续 5 行内说明"移除条件"。

检查方式：
```bash
scripts/check-workaround.sh XrPlayer/
```

此检查不在 SwiftLint 中实现（单行正则无法可靠检测多行模式），而是通过独立脚本执行。
