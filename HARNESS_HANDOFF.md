# 回归 harness:现状与需求

## 一句话

**有一个 runner,没有一个 harness。** runner 是进程级的(启动、停止、发指令);
"等多久、平台差异怎么处理、证据何时有效"这些策略散在五个驱动器里,靠每个作者记得。

## 规模

| 目录 | 文件 | 行数 |
|---|---|---|
| `Scripts/verification` | 41 | 39,714 |
| `Scripts/rules` | 122 | 54,216 |
| `Scripts/regression` | 15 | 13,350 |

最大两个文件:`regression_operation_adapter.py` 8,424 行、`reachability_matrix.py` 7,428 行。

## 结构

**runner 只有一个**:`Scripts/verification/interactive_visionpro_ui.py`。所有回归都经过它。

**五个驱动器各自为政**:

| 驱动器 | 自定义超时常量 | 裸调 `timeout=` |
|---|---|---|
| `reachability_matrix` | 9 | 111 |
| `playback_mode_matrix` | 7 | 6 |
| `regression_operation_adapter` | 1 | 15 |
| `regression_preparation_adapter` | 0 | 0 |
| `measure_controls_flash` | 0 | 0 |

同一个 runner、同一批动作,每个调用方各定一套等待策略。

## 关键事实

**测量数据早就存在,无人读取。** `Scripts/verification/controller_timings.json`
保存两条 lane、每个动词最近 20 个样本。2026-09-01 之前所有超时都是手写字面量。

**真机与模拟器的实测差异**(旧代码,20 样本/项):

| 动作 | 真机 p95 | 模拟器 p95 |
|---|---|---|
| tap | 8.6s | 13.5s |
| snapshot | 5.8s | 14.2s |
| relaunch | 9.9s | **19.0s** |

模拟器交互更快(tap 2.3s vs 4.1s),重启更慢。

**平台差异有出口但被绕过。** `enchron_target.py` 提供 `copy_from_container` /
`copy_to_container` / `truncate_in_container` 按 lane 分流。2026-09-01 在
`reachability_matrix` 里发现 5 处硬编码 `devicectl --device <CoreDevice>` 绕过它,
在模拟器上必然失败。其余四个驱动器未审计。

## 当前超时值与依据

| 常量 | 值 | 依据 |
|---|---|---|
| `INTERACTION_TIMEOUT` | 20s | 两条 lane p95 × 1.5 |
| `READ_TIMEOUT` | 20s | 同上 |
| `RELAUNCH_TIMEOUT` | 30s | 同上 —— **本轮模拟器实测撞满 30s,值不足** |
| `APPEARANCE_TIMEOUT` | 8s | 40 次轮询,13 次成功全在第一轮 |
| `HALT_TIMEOUT` | 60s | **未测量** |
| `SESSION_TIMEOUT` | 300s | **未测量**,旧样本含已删除的 180s 等待 |
| `PROBE_COPY_TIMEOUT` | 120s | **未测量** |

## 需求

1. **等待策略需要单一归属。** 现在五个驱动器各写一套,改一处不影响其余四处。
2. **超时必须由测量导出,不能手写。** `controller_timings.json` 已有数据,需要有人读它。
3. **平台差异需要单一出口且强制。** 现有出口可被绕过且无检查。
4. **仪器故障与产品失败必须可区分。** 已部分实现(`silentTaps`、
   `journalRetrieved`、失败原因链),需要成为契约而非个案。
5. **证据生命周期需要定义。** 恢复动作(`ensure_session`)会销毁探针日志与响应批次;
   段落开始前是否清空、由谁负责,目前靠副作用。
6. **两条 lane 并行需要共享状态的所有者。** 冻结文件曾被两条 lane 竞争写入。

## 已知未解

- 真机 `xcodebuild` 退出前跑 `devicectl diagnose`,一次实测卡约 1 小时后失败。
  模拟器 0 次。同一日志有两条产品警告:`scene invalidated before create completion`、
  `Modifying state during view update`。
- `ensure-session` 离群值:真机 268s、模拟器 238-263s(旧代码,20 样本中各约 20%)。
- 可达性矩阵 219 格,31 条 known-defect,其中 23 条已修待验证。
