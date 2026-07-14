# 节点 3：Provider Open Snapshot

## 作用与边界

节点 3 让节点 2 选定的 Video Sample Provider 打开当前来源，并把 open-time container、video track、codec、timing 和 metadata 事实写成 Provider Open Snapshot。连续 event 和 sample 从节点 5 开始。

```mermaid
flowchart LR
    Session["Media Session + Route Binding"] --> Request["Provider Open Request"]
    Request --> Provider["Selected Video Sample Provider"]
    Provider -->|opened| Snapshot["Provider Open Snapshot"]
    Provider -->|failed| Failure["Provider Open Failure Record"]
    Snapshot --> Track["Node 4 Video Track Model"]
```

## Route adapters

- Apple Compressed：`AVURLAsset` / `AVAssetReader` 所见的 asset、video track、format descriptions 和 storage-sample capability。
- FFmpeg Compressed：`AVFormatContext` / selected video stream / codec parameters / compressed sample configuration。

## Snapshot fields

- schema version、Media Session ID、route、source summary、provider kind。
- open status、container / demuxer summary、duration、seekability。
- observed video tracks 和 selected raw track mapping。
- codec name / id / tag、profile / level（可见时）、dimensions、nominal frame rate、timebase。
- codec configuration / extradata summary。
- color primaries、transfer function、YCbCr matrix、range、HDR / Dolby Vision signaling summary。
- normalized facts 与 provider-observed extras。

事实确认不存在用 `none`，当前无法确定用 `unknown`，Provider 没通过 seam 暴露用 `notExposed`，当前明确不支持用 `unsupported`。

## Failure record

记录 Media Session、route、source summary、failure stage、provider error code / message 和 recoverability。no video track、container open failure 与 reader output rejection 分别分类，不能都压成 unknown。

## 完成条件

唯一完成条件：当前 Provider 已打开来源并提交 Provider Open Snapshot。Snapshot 不声明 sample、renderer 或画面成功。

## 验收方向

每条 route 有独立 L1 / L2 open case。测试断言 normalized facts、route provenance 和节点 3 不产出连续 sample / renderer facts。
