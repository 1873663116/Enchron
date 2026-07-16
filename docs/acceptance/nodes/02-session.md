# 节点 02：Media Session

## 边界

节点 02 对 `open(source:)` 做 admission。accepted open 创建 Media Session、Media Source Record、Open Operation，并占用唯一 Current Media Slot；Provider prepare 从节点 03 开始。

## 输入与输出

输入包含节点 01 source facts、initial presentation time、initial paused state 与 preferred rate。输入不是裸 URL，PlaybackCore 不能从 URL 猜测 provenance 或访问要求。

accepted open 输出唯一 Media Session ID、不可变 Media Source Record、Current Media Slot change 与 running Open Operation。rejected open 输出带 reason 和 slot state 的 Open Rejection Record，不创建 session。

## 稳定规则

- 同一时刻最多一个 active Media Session。
- source 与初始播放意图在 session 内不可原地替换。
- 只有 Current Media Slot 的 session 可以更新 lifecycle、diagnostics 和 renderer facts。
- 旧 session callback 只能记录为 stale。
- close 或不可恢复 failure 的 cleanup barrier 完成后才能释放 slot；ended 不自动释放。

## 完成条件

唯一完成条件：source 与初始播放意图已不可变绑定到新的 Media Session，且该 session 占用 Current Media Slot。

## 验收

L1 验证 accepted/rejected、唯一 session、slot occupancy/release、close/reopen 新 identity、并发 open 和 stale update rejection。
