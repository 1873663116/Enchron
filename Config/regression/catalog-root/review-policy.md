---
{"perPacketLimit":{"inputTokens":32000,"reviewItems":12},"schema":"enchron.regression.review-policy","schemaVersion":1,"totalBudget":{"inputTokens":2000000,"reviewItems":4096}}
---

# Catalog 评审预算策略

每个 packet 最多包含 12 个审查单元，输入上限为 32,000 token。总预算同时约束输入量与审查单元数；两个单位中任一项不足，评审计划都不能生成完成态。

预算只负责证明资源覆盖完整 packet，不允许减少必审 Promise、Fact、Preparation、Operation、Oracle、Rubric、Journey 或 Scenario，也不允许删除某类 reviewer。某个单元超过单包上限时，应当先改善合同粒度或提高显式预算，不能静默截断其内容。
