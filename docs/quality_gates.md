# 验证与验收

- Status: 活法律（骨架版——细则随阶段 2 验证轮迭代，修订走收尾协议）。
- Purpose: 定义「什么证据让一个改动可信」与「怎样算验收通过」。

## 证据分级阶梯

自动检查 < 构建通过 < 模拟器 < 真机 < 人类体验。

交付时声明爬到了哪一级、为什么对这个改动足够。build pass 不证明空间交互、HDR、沉浸视频、舒适度、音频或性能正确；模拟器不证明真机——HDR/EDR、亮度、撕裂、功耗、长时间观看只在真机与人眼可见。自动化与人类验证回答不同的问题，交接时分开陈述。

## 验收条件前置

- issue 动工前 body 写明「怎样算完成」；验收条件不满足不关单。
- 证据原件（截图、日志、`nm` 输出、录屏）贴 issue 评论；仓库不进二进制证据。
- PR 描述必带 `Closes #N`。

## 每轮一次人类验收

收尾时把待裁决项呈进驾驶舱决策队列；人类裁决结果回流 issue（关闭/重开/改验收条件），属决策者写 ADR。

## 风险路由

- 纯 Domain/UseCase → `swift test`；触 app target、UI、asset、scene lifecycle、entitlement、RealityKitContent → 匹配 scheme 的完整构建。
- 播放、mpv、Metal、CoreVideo、桥接、线程、HDR、远程 I/O、持久化 → 升 `xcodebuild analyze`。
- 选 API 前先答两问：哪个 visionOS surface 拥有此行为？哪个 MediaProfile 拥有此内容？平台敏感改动走 `.agents/skills/visionos-platform`。
- 性能、掉帧、内存、启动、长时间观看 → Instruments / `xctrace`。
- 命令样例与证据选择表：`docs/reference/apple-toolchain-guide.md`。

## 发布两种真相

技术就绪 ≠ 分发就绪。archive 成功只证明能出包；signing、隐私、license（含 MPVKit-GPL）、export compliance、TestFlight 反馈是另一条线，全部属于人类裁决边界（见 CLAUDE.md 硬边界）。
