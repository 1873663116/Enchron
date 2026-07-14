# 运行产物边界

本目录保存历史运行产物，不是当前设计或当前通过状态的真相源。设计只看 `docs/core-spec.md`，验证合同只看 `docs/acceptance/verification-system.md`，每份产物当前是否仍有效只看 `docs/acceptance/evidence.md` 中对应 Evidence ID 的状态。

JSON 内的 `completed` 或 `passed` 只表示生成它的旧 manifest 当时如何判定，不能跨源码、fixture、route matrix 或 presentation topology 继承。尤其是现有 `vision-device-presentation-*.json` 均早于当前“独立 Control Window、单一 Playback Window、单一 progressive ImmersiveSpace、49 个精确 case、无 probe 专属编排”的合同；无论文件内部布尔值为何，都不得用来声明当前 visionOS 实现通过。

`visionos-presentation-probe.md` 是当前运行协议，不是当前通过结果。文件名、脚本名和 flag 中保留的 probe 只表示代码驱动输入入口；它不拥有另一套 scene、binding、mode 或 rollback 编排。当前 host contract tests 与 code-signing-disabled generic visionOS build 已在同一 working tree 通过，精确边界见 `2026-07-13-current-visionos-presentation-contract.md`；它们不能替代 49-case 真机结果。

本协议不授权真机执行；签名、安装或启动 Vision Pro 前，仍须操作者针对当次运行明确确认设备已佩戴、解锁且可测试。
