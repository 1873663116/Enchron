# ExecPlan045 — T3.1 Health Score 补全（90.5% → ≥95%）

**创建时间**: 2026-04-02  
**Pipeline State**: VERIFYING（Phase 3 T3.1 回归验证补全轮）  
**本轮目标**: 修复剩余 PARTIAL/FAIL 项，使 Health Score 从 90.5% 提升至 ≥95%

---

## 背景

Round 25 完成后：
- PASS: 49, PARTIAL: 7, FAIL: 2, DEFERRED: 1（总 58）
- Health Score: 90.5%（目标 ≥95%，差 260 pts）

距 95% 差距：(95% × 58) - (49×100 + 7×50) = 5510 - 5250 = **260 pts**

## 修复计划

| 修复项 | 当前状态 | 目标 | 分值 |
|--------|----------|------|------|
| QA-L05 缓存清理 UI | FAIL | PASS | +100 |
| QA-B01 元数据显示（codec/时长） | PARTIAL | PASS | +50 |
| QA-M03 P2 VoiceOver（FileBrowser/Settings/ImmersiveSpace） | PARTIAL | PASS | +50 |
| 调查其余 PARTIAL 项，修复 ≥2 项 | PARTIAL | PASS | +100 |

**预计总增益**: ≥300 pts → Health Score ≥ (5250+300)/58 = 5550/58 = **95.69%** ✓

## 具体修复内容

### QA-L05: 缓存清理 UI
- 在 `SettingsView.swift` 的 "Storage" Section 添加"清理缓存"按钮
- 调用 `CacheService` (或等效服务) 的清理方法
- 按钮触发后显示确认反馈（".alert" 或 ProgressView）

### QA-B01: 元数据显示
- `VideoDetailView.swift` 当前只显示分辨率和帧率
- 需补充：编码格式（codec）+ 视频时长（duration）
- 从 `VideoFile.metadata` 或 mpv 的 `videoCodec`/`duration` 属性读取

### QA-M03 P2: VoiceOver 补全
- `FileBrowserView.swift`：为文件行、文件夹行、操作按钮添加 `accessibilityLabel`
- `SettingsView.swift`：为设置项 Toggle/Slider 添加 `accessibilityLabel`
- `ImmersiveSpaceView.swift`：为虚拟屏幕、环境切换按钮添加标签

### 其他 PARTIAL 项调查
- 检查批次 1 报告中剩余 PARTIAL（浏览 /Movies/、UI 布局等）
- 找最容易修复的 2 项

## 验收标准
- `swift build` 零 error
- `swift test` ≥ 248 pass, 0 fail
- QA 路径 L05/B01/M03 验证 PASS
- 计算新 Health Score ≥ 95%
