# 阶段 2 作战地图 — mpv 正式接入 visionOS

- Purpose: 本轮唯一作战地图：轮级假设、issue 索引、证据与堵点登记。
- Status: Active（T1–T6 issue 全关 → 本图归档进 `docs/archive/plans/`，驾驶舱切阶段 3）。
- **执棒者：云端**（文档轮收尾后交棒 mac 做 T1）。

## 目标（一句话）

一个常驻纹理环喂三个呈现表面（虚拟屏 / 窗口平面 / 全景球），三模式往返切换 mpv 全程不重启——SDR 即可，堵点只登记不展开。

## 工作假设（拍板 2026-06-10）

单出口（出口 A 仅对照组）/ 窗口载体 RealityView 平面 / App 分支宿主、虚拟屏面片代码生成、RCP 资产不动 / MPVKit→自产 XCFramework **限分支范围**（合 main 前再次确认）/ HDR 全部记 C9 名下。

终判挂 E6。理论底座与 C/E 清单：`docs/reference/2026-06-10-frame-pipeline-theory-investigation.md` §4–§6。

## 任务索引（详情、验收条件、证据都在 issue）

串行链：**T1 [#22](https://github.com/1873663116/XrPlayer/issues/22) 打包 → T2 [#23](https://github.com/1873663116/XrPlayer/issues/23) 冒烟 → T3 [#24](https://github.com/1873663116/XrPlayer/issues/24) 贴面 → T4 [#25](https://github.com/1873663116/XrPlayer/issues/25) 路由 → T5 [#26](https://github.com/1873663116/XrPlayer/issues/26) 真机 → T6 [#27](https://github.com/1873663116/XrPlayer/issues/27) 登记收尾**。前置 issue 关闭后，由收尾清扫升标 `ready-for-agent`；当前仅 #22 可领。

标记类（全部等管线验证后）：#19 代码重构、#20 测试重构、#21 UI 重构与新设计接入。归档清扫 #18 由文档轮 PR 关闭。

## 证据登记（日期 / 谁 / 指针——原件贴 issue 评论，此处只记里程碑一行）

（空）

## 堵点登记（C12 起编号；HDR 一律并入 C9 不展开）

（空）

## 风险提醒

- C6（`VK_EXT_metal_objects` on visionOS MoltenVK）单点最大未知，T2 首撞；失败回 fork 调整导入机制，本图暂停并更新调查文档。
- `pl_gpu_finish` 全停（C10）本轮容忍，只记帧率观感。
- `check_nonzero` 抽样是验证夹具，生产接入时移除（fork CLAUDE.md「剩余」）。
