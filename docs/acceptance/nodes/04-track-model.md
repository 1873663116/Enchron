# 节点 04：Track Model

## 边界

节点 04 把 Provider Open Snapshot 的 raw track facts 转换为 PlaybackCore-owned video、audio 与 subtitle track identity、格式事实和选择结果。它不泄漏 provider 私有对象，也不创建 sample。

每条 track 至少记录 opaque Track ID、raw source mapping、media kind、codec/format/timing facts、language/role（可见时）、selected 与 not-selected reason。Track ID 不等于 FFmpeg stream index、AVAsset track identity 或 UI row identity。

## 稳定规则

- video lane 必须有一个可用 primary track，否则节点失败。
- audio 与 subtitle 可以为空；不存在的轨道不能伪造成默认轨道。
- 用户选择使用稳定 Track ID，核心内部再映射到 raw identity。
- 音轨切换是当前 Media Session 内的 transaction；失败恢复旧轨和播放意图。

## 完成条件

唯一完成条件：当前 Media Session 已建立稳定 Track Model，并确定 active video、audio 和 subtitle selection。

## 验收

L1 验证多轨、无音频、双音轨、语言、missing facts、selection、not-selected reason、音轨切换 rollback 与跨 reopen identity 规则。
