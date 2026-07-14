# 节点 2：Media Session and Route Binding

## 作用与边界

节点 2 对 `open(source:route:)` 做 admission。accepted open 创建 Media Session、Media Source Record、Route Binding Record、Open Operation 并占用 Current Media Slot。Provider prepare 从节点 3 开始。

## 输入

- 节点 1 source facts。
- 显式 Playback Route。
- initial presentation time。
- initial paused / rate state。

输入不是裸 URL。source provenance、privacy-safe summary 和 access requirement 不能由 PlaybackCore 从 URL 猜测。

## 输出 records

accepted open 产出：

- Media Session ID。
- immutable Media Source Record。
- immutable Route Binding Record。
- Current Media Slot change record。
- Open Operation identity，初始 state 为 `running`。

rejected open 产出 Open Rejection Record，至少包含 reason、source summary、requested route 和 slot state；它不创建 Media Session。

## 稳定规则

同一时刻最多一个 active Media Session。同一 Media Session 的 source 和 route 不可原地替换。route change 必须 cold switch：cleanup 旧 session，再创建新的 Media Session。

只有 Current Media Slot 中的 Media Session 可以更新当前 facts。旧 session callback 可以记录为 stale，不能更新 lifecycle、diagnostics、renderer 或 presentation。

slot 只在 close cleanup 完成或不可恢复 failed 已记录后释放。`ended` 不自动释放 slot。

## 完成条件

唯一完成条件：source、route、initial state 已不可变绑定到新的 Media Session，且该 session 占用 Current Media Slot。Provider 是否打开成功属于节点 3。

## 验收方向

L1 验证 accepted / rejected、unique session、immutable binding、slot occupancy / release、cold switch 新 identity 和 stale update rejection。L2 验证公开 App entrance 观察到同一事实。
