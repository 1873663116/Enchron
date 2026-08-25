# Phase 6：renderer 跨场景重绑定探针（已裁决，无剩余工作）

[overview](overview.md)

## 裁决（2026-08-11 真机实测）

重绑定失败。同一技术 session 的 renderer 在旧场景组件销毁后，于新场景 entity 上以新组件包装同一 renderer：组件停留在 loading，解码输入与 renderer 时间持续推进（1373→2818 帧输入、22→46 秒），displayed-frame 计数停滞，物理截图全黑，无崩溃、无 flush 请求、无显式 RealityKit 拒绝；30 秒落定边界以 spatialPlaybackSurfaceUnavailable 回退。结论：跨 RealityView 的 renderer 转移不可行，横向边保留技术 session 重建实现（phase-7）。

证据出自 2026-08-11 的 renderer-rebind-probe 会话（探针日志、截图序列、xcresult），该目录已随证据清理删除；探针代码未并入产品。决定性转换 E096ACD0-CB71-419C-97C3-5AA48C9F1369。上文的帧数与秒数是这轮探针的读数，重跑需重建探针。

## Changes

无。探针代码已按计划撤出工作区。
