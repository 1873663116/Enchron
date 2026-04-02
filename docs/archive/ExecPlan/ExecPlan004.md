# ExecPlan004 — T0.4 E2E QA 测试路径设计

> Round: 4
> Phase: PLANNING
> 目标: 为 T0.1 功能清单中每个 🟡/🔴 项设计端到端 QA 测试路径
> 产出: docs/qa-plans/qa-plan-v3-comprehensive.md

## 输入

- `docs/qa-plans/feature-inventory-v3.md` — 82 个功能点（16🟢/46🟡/16🔴/4⚪）
- `workspace-agents/Requirements.md` — 用户视角需求
- `docs/qa-plans/helloworld-ux-audit-v3.md` — 12 项 UX 对比
- 12 个测试素材（T0.3 已验证）

## 设计原则

1. 每条路径模拟**真实用户操作序列**（启动→浏览→选择→播放→交互→返回）
2. 每条路径包含**具体预期结果**（不接受"检查是否正常"）
3. 标注验证类型：Simulator（可在模拟器执行）/ Structure（代码路径验证）/ Human-only（需真机）
4. 使用实际测试素材文件名

## QA 路径分类

| 类别 | 路径数 | 覆盖功能 |
|------|--------|---------|
| A. 启动与导航 | 3 | F2.1-F2.9 |
| B. 文件源管理 | 4 | F1.1-F1.4, F2.5 |
| C. 窗口模式播放 | 5 | F3.1, F1.5-F1.14 |
| D. 沉浸影院模式 | 5 | F3.2, F6.1-F6.7 |
| E. 全景模式 | 5 | F3.3, F1.17-F1.19 |
| F. 3D 立体视频 | 3 | F1.15-F1.16 |
| G. 播放控件 | 7 | F3.10-F3.21 |
| H. 手势交互 | 4 | F3.5-F3.9 |
| I. 状态管理 | 5 | F4.4-F4.10 |
| J. 错误处理 | 3 | F4.1-F4.3 |
| K. HDR/色彩管理 | 4 | F5.1-F5.4 |
| L. 设置与偏好 | 4 | F7.1-F7.6 |
| M. 辅助功能 | 3 | F8.1-F8.5 |
| **总计** | **55** | 78/82（排除 4⚪） |

## 执行步骤

1. Supervisor 设计全部 55 条 QA 路径
2. 写入 `docs/qa-plans/qa-plan-v3-comprehensive.md`
3. 更新 overnight-log.md
4. Git commit
