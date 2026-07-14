# PlaybackCore 验证系统

本仓库只验证 library 行为，不拥有 App、UI、RealityKit 或设备观感验收。

## 层级

- L1：swift test，证明 records、admission、Provider seam、控制状态机、audio/video graph、format override、stale rejection 和 cleanup barrier。
- L2：独立 probe 工具验证真实 container / sample / FFmpeg bridge 与 Apple compressed reference 行为。
- Consumer：调用方自行验证 renderer consumer、可见画面、可听输出、平台 presentation 与主观观感；结果不写成本仓库完成条件。

## 节点规则

节点 1–8 分别产生 record。每个用例只有一个预期结果；一条路线成功不能推断另一条路线成功。失败必须在发生节点终止，不能由下游隐藏补救。

## 证据规则

有效证据必须记录当前 Git revision、fixture identity、命令、结果和失败边界。历史 App 运行结果只能作为历史背景，不能证明当前 library。
