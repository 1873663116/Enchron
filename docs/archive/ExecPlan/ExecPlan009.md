# ExecPlan 009 — E2E Simulator QA 测试

**Round**: 11
**Phase**: VERIFYING
**Pipeline State**: VERIFYING
**Created**: 2026-04-02

## 目标

在 Apple Vision Pro Simulator 上执行端到端 QA 测试，覆盖 TODOS.md T2.1 全部测试项。
这是最后两个终止条件的关键验证步骤。

## 测试范围

1. 文件浏览（本地 / SMB / WebDAV / Photo Library）
2. 视频详情二级界面（VideoDetailView 导航、元数据展示、轨道选择）
3. 播放启动流程（prepare → confirm，Resume/Start Over）
4. 播放控件交互（统一时间轴、精确时间标签、逐帧步进）
5. 沉浸空间开关（全局入口 + 播放内）
6. 屏幕位置 / 旋转控件
7. 播放结束行为（Stop / Repeat / Play Next）
8. 进度指示（橙色圆点 + Watched）
9. 网络重连机制
10. 缓存清理

## 测试视频

- SDR: /Users/xiongzhipeng/Movies/SDR-test.mkv
- HDR10: /Users/xiongzhipeng/Movies/HDR10-test.MP4
- Dolby Vision: /Users/xiongzhipeng/Movies/dolby-vision-test.mp4
- 180°: /Users/xiongzhipeng/Movies/180-vr-test.mp4
- 360°: /Users/xiongzhipeng/Movies/360-nasa-test.webm

## 方法

使用 /qa skill 执行系统化测试（xcodebuild + simctl + 自动化编排）

## Decision Log

（执行中填充）
