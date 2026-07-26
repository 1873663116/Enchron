# 节点 01：Source

## 边界

节点 01 从 Enchron 的 Media Reference 开始，在 PlaybackCore 的公开 open 接口结束。Enchron App 负责解析系统文件、Photos、SMB 或 WebDAV 引用，取得本次访问所需授权，并形成核心可消费的 Media Source；PlaybackCore 只接受已经解析的来源事实，不负责长期授权或远程目录语义。

## 必须记录

- source request identity、provenance 与 privacy-safe summary。
- 原始 Media Reference identity 与本次可读取 locator 的关联。
- access requirement、access lease 状态与释放责任。
- 本地文件、Photos、远程 range bridge 或 verification fixture 的明确来源类型。
- 交付的目标公开接口；产品入口不得携带 Playback Route。

完整私有路径、凭据和 access token 不进入默认日志或 evidence。verification fixture 必须标记为 test provenance，不能冒充系统文件选择器。

## 完成条件

唯一完成条件：稳定的 source facts 与有效访问生命周期已交给 `open(source:)`。节点 01 不创建 Media Session，不探测 container，也不声明媒体可播放。

## 验收

L1 验证 source schema、privacy 和 rejection；App integration 验证 file bookmark、Photos identifier、SMB/WebDAV range source、取消、授权失效与 cleanup 后释放。
