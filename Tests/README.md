# XrPlayer 测试目录说明

推荐先看：
- [`docs/test_inventory.md`](../docs/test_inventory.md)
- [`docs/quality_gates.md`](../docs/quality_gates.md)

## 运行方式

```bash
swift test
```

## 当前测试覆盖重点

- 基础播放规则
- 手势消歧状态机
- HDR / SDR 配置安全性
- SMB / WebDAV 基础适配行为
- Keychain / 数据源模型

## 当前测试未充分覆盖

- 真机 UI / UX 体验
- 二级进度条可用性
- 冷启动首帧体感
- 沉浸空间真实表现
- 肉眼可见的 HDR 视觉正确性

## 维护原则

新增修复时，优先补：
1. 回归测试
2. 阶段日志
3. smoke checklist

不要只修代码，不留下可复用证据。
