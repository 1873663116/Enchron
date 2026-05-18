# ExecPlan024 — v3 Round 1: T0.1 功能全清单提取

> Pipeline State: PLANNING
> 目标: T0.1 — 从用户视角提取每一个可感知功能，分类标注实现/验证状态
> 预期产出: docs/qa-plans/feature-inventory-v3.md

## 步骤

1. **并行阅读所有需求与设计文档**
   - Requirements.md 2.1-2.5
   - product_philosophy.md
   - design_docs/ 全部文件
   - 现有代码结构（确认实现状态）

2. **提取功能清单**
   - 按用户视角（不是代码路径）
   - 分类：🟢 已实现已验证 / 🟡 已实现未验证 / 🔴 未实现或缺素材 / ⚪ MVP 外

3. **特别关注 TODOS.md 指出的被忽略领域**
   - 空间手势消歧
   - 播放模式自动切换 UX
   - 网络异常用户行为
   - 播放记忆恢复
   - 播放结束行为
   - 缓存清理
   - 视频格式测试素材

4. **输出到 docs/qa-plans/feature-inventory-v3.md**
