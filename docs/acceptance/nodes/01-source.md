# 节点 1：Source Acquisition

## 作用与边界

节点 1 由 App Adapter 通过系统文件选择器、document-open 或明确的 test entrance 取得媒体 locator，并形成 PlaybackCore 可以接受的 source facts。open admission 属于节点 2；媒体是否可读、容器和 codec 事实属于节点 3。

输入边界：system document entrance → App Adapter。

输出边界：App Adapter → `open(source:route:)`。

## 输出 records

成功输出 Source Acquisition Record：

- source request identity。
- locator。
- provenance：`systemFileImporter`、`documentOpen`、`testAutomation` 或未来稳定值。
- privacy-safe summary。
- access requirement 与本次 access observation。
- delivery target：公开 PlaybackCore control interface。

失败输出 Source Acquisition Failure Record。取消或 cleanup 输出 `terminatedByCleanup`。验证 App / Lab 的固定 fixture 入口必须标为 `testAutomation`，不能冒充系统文件选择器。

## 稳定规则

App Adapter 拥有长期 security-scoped access；节点 1 只记录本次来源取得事实。完整私有 path 不进入默认日志和 evidence。节点 1 不创建 Media Session，不探测容器，不选择 route，也不产出 sample。

## 完成条件

唯一完成条件：完整 source facts 已交付公开 `open(source:route:)`。媒体可播放不是本节点结果。

## 验收方向

L1 验证 record schema、privacy-safe summary 和 failure / cancel。L2 分别验证 test handoff 与系统 document entrance；两者是独立用例。
