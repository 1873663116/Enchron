# 节点 03：Provider Open Snapshot

## 边界

节点 03 让当前 Media Sample Provider 打开来源，并把 open-time container、轨道、codec、timing、color、HDR、projection 与 stereo 事实固化为不可变 Provider Open Snapshot。连续事件从节点 05 开始。

产品 provider 使用 FFmpeg 读取 container 并解封装。Apple compressed provider 只存在于 verification scenario，用于生成 AVFoundation storage-format 对照 sample；provider provenance 必须进入证据，但不得进入产品路线选择。

## Snapshot

- schema、Media Session ID、source summary 与 provider provenance。
- open status、container/demuxer、duration 与 seekability。
- observed video、audio、subtitle tracks 与 raw source mapping。
- codec/tag/profile/level、dimensions、frame rate、timebase 与 codec configuration。
- color primaries、transfer、YCbCr matrix、range、HDR/Dolby Vision、projection 与 stereo facts。

事实确认不存在使用 `none`，当前无法确定使用 `unknown`，provider seam 未暴露使用 `notExposed`，明确不支持使用 `unsupported`；不能用默认值填补缺失。

## 完成条件

唯一完成条件：当前 provider 已打开来源并提交 Provider Open Snapshot。它不声明 sample、renderer、displayed frame 或音频成功。

## 验收

L1 对产品 FFmpeg provider 和 Apple reference provider 分别验证真实 container、缺轨、损坏来源、网络 read failure、color/HDR facts 与 provider provenance。
