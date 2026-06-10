# 阶段 2 作战地图 — mpv 正式接入 visionOS

Purpose: 本轮验证的唯一作战地图：目标、终点判据、证据登记、堵点登记、会话交接快照。
Status: Active plan（本轮结束后归档进 `docs/archive/`）。
Owner/scope: 人类拥有决策与真机验收；agent 拥有代码、文档与构建执行。理论底座见 `docs/reference/2026-06-10-frame-pipeline-theory-investigation.md`。

---

## 目标（一句话）

把 fork 的常驻纹理出口接进 XrPlayer：一个纹理环喂三个消费者（虚拟屏、窗口平面、全景球面），App 侧路由三种模式且 mpv 全程不重启——SDR 即可，堵点只登记不展开。

## 本轮已拍板的工作假设

| 决策 | 选择 | 出处 |
|---|---|---|
| 出口拓扑（D1 工作假设） | 单出口：三种模式都消费常驻纹理；出口 A 仅作对照组 | 调查文档 §5，终判挂 E6 |
| 窗口载体（D2 工作假设） | RealityView 平面（最简形态） | 同上 |
| 验证宿主 | XrPlayer App 分支内直接做；验证场景挂在现有 `Immersive.usda`（RCP 场景已存在），虚拟屏面片代码生成、不动 RCP 资产 | 本计划 |
| 依赖替换 | MPVKit 官方包 → 自产 XCFramework，**分支范围内已获人类授权**，合入 main 前再次显式确认 | 人类裁决项 |
| HDR | 本轮不做，一切 HDR 堵点记入 C9 名下 | ADR 0004（出口为 SDR 契约） |

## 终点判据（全部勾完 = 理论验证打通）

- [ ] **T1 打包**：enchron 合入 MPVKit `0001` patch → `xros` + `xrsimulator` XCFramework；`nm` 确认 `xr_resident_*` 四符号存在
- [ ] **T2 冒烟**：App 分支换依赖后，`macvk_resident` 初始化成功、双 IOSurface 配置成功、front ID 翻转（日志可见）；模拟器先行
- [ ] **T3 贴面**：同一纹理环喂三个消费者，SDR 画面正确——
  - [ ] `Immersive.usda` 场景内虚拟屏面片
  - [ ] 窗口模式 RealityView 平面
  - [ ] 全景球面（全景种子）
- [ ] **T4 路由**：窗口 ↔ 沉浸 ↔ 全景往返 ≥10 次，无黑帧/崩溃/泄漏，mpv 不重启
- [ ] **T5 真机抽查**：T3 至少在 Vision Pro 真机目检一次（撕裂、色彩）；模拟器不算终审
- [ ] **T6 登记**：新堵点已编号（C12 起），调查文档 C 清单状态已更新

对应理论论断：T1→C3 终判，T2→C5/C6，T3→C8（SDR 部分），T4→单出口收益实证，T5→C11 边界。

## 执行侧分工（谁在哪干活）

- **mac 本地（你 + 本地 agent 会话）**：T1 打包（需 Xcode/MPVKit 构建链）、所有构建/模拟器/真机运行证据、RCP 资产编辑。
- **云端 agent 会话**：消费端 Swift 代码（采样器、面片实体、路由）、文档维护、fork 侧 C 代码改动的编写（编译验证仍回 mac）。
- 云端会话**不能**出构建证据——Linux 容器无 Apple 工具链。计划内勾选 T1–T5 的权力归 mac 侧证据。

## 证据登记（随勾选追加，格式：日期 / 谁 / 证据指针）

（空）

## 堵点登记（C12 起编号；HDR 一律并入 C9 不展开）

（空）

## 已知风险提醒（来自调查文档，不重复展开）

- C6（`VK_EXT_metal_objects` on visionOS）是单点最大未知，T2 最先撞它；失败则回 fork 调整导入机制，本计划暂停并更新调查文档。
- `pl_gpu_finish` 全停（C10）本轮容忍，只记帧率观感。
- `check_nonzero` 抽样是验证夹具，生产接入时移除（fork CLAUDE.md「剩余」）。
