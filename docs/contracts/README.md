# Enchron Contracts

这个目录承载两类不同但相关的文档：

1. 规范性契约
2. 具体 API 参考

不要把它理解成“只有 OpenAPI 的目录”。

这里的“前端 / 后端”是协作分工语义：

- 前端指 UI、交互、呈现与用户可见状态
- 后端指客户端内部的业务逻辑、数据访问抽象与接口契约设计

它不默认等同于“客户端 / 独立服务器”的部署划分。

## 目录结构

- `frontend-backend-contract.md`
  规范性文档。定义前端 / 后端边界、协作方式、变更规则、版本策略。
- `openapi.yaml`
  具体 API 参考。定义远程数据访问相关的请求 / 响应 / 错误模型。
- `examples/`
  示例 payload、mock 数据、契约样例。

## 使用原则

- 需要判断职责边界、协作规则、谁先改什么时，先读 `frontend-backend-contract.md`
- 需要看字段、schema、错误结构、接口形状时，读 `openapi.yaml`
- 需要 mock 数据或联调用例时，读 `examples/`

## 维护规则

- 规范性契约和 API 参考必须长期同步维护
- 若远程数据模型、字段语义、错误结构、交互流程发生变化，必须同时更新：
  - `frontend-backend-contract.md`：如果边界、流程、协作规则被影响
  - `openapi.yaml`：如果接口、schema、错误模型被影响
  - `examples/`：如果样例 payload 已失真
- 不允许只改实现、不改契约
