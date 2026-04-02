# ExecPlan 034 — P1 手势缺陷修复 (F3.9 + H03)

## 目标
修复两个手势相关 P1 缺陷：
1. **QA-H04 / F3.9**: 捏合拖拽进度条 — `.drag` case 为 `break` 空操作，需实现拖拽手势处理
2. **QA-H03 / H03**: 长按速度恢复 — 松开长按时 hardcoded 恢复 1.0x，应恢复用户设定的原始速度

## 步骤
1. 调研：读取手势相关代码，定位 `.drag` case 和 longPress 逻辑
2. 修复 H03：保存长按前的播放速度，松开时恢复
3. 修复 F3.9：实现拖拽手势处理（进度条 seek 或其他合理交互）
4. Build + Test 验证
5. Commit

## 验收
- swift test 全绿 (≥248)
- swift build 零 error
- QA-H03 PARTIAL → PASS
- QA-H04 FAIL → PASS 或 PARTIAL
