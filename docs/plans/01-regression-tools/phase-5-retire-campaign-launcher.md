[← overview](overview.md)

# 阶段 5：删批量 campaign 启动入口

## 目标

删掉按 segment plan 并发拉起多个 lane 进程的启动器。它没有生产消费者。

## 改动清单

- 删 `Scripts/verification/run_campaign.py`（83 行）。唯一导入 `harness.campaign` 的生产文件。
- 删 `Scripts/rules/test_campaign_launcher.py`（186 行）。它是 `run_campaign.py` 的唯一消费者，:104、:156、:172 三处导入 `harness.campaign`。
- 删 `Scripts/verification/harness/campaign.py`。导出 `CampaignNotParallelizable`、`default_spawn`、`launch`、`segment_command`。上面两个文件删除后无导入方。

`Scripts/verification/harness/parallel.py` 保留。它有自己的 campaign 形状拒绝逻辑（:80-111），被 `Scripts/verification/reachability_matrix.py:8127` 的 `_campaign_serial_refusal` 使用，与 `harness/campaign.py` 是两份独立实现。`Scripts/verification/harness/lane_partition.py` 同样保留，`generate_reachability_segment_plan.py:46` 与 `reachability_matrix.py:36` 都依赖它。

删除之前确认无遗漏导入方：

```sh
grep -rn "harness.campaign\|run_campaign\|CampaignNotParallelizable\|default_spawn" \
  --include="*.py" --include="*.md" --include="*.json" --include="*.yml" . \
  | grep -v "^./.git/"
```

## 数据结构与形态

删除的对外形状：

```text
run_campaign.py --campaign --execution-input --segment-plan --output-root
                --simulator-target --device-target
  -> {segment id: [exit code]}，退出码取全部段的最大值
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/verify_scripts_inventory.py
```

`verify_scripts_inventory.py` 是本阶段的关键判据。它要求 `Scripts/` 下每个脚本的文件名在仓库别处被引用；删掉入口而漏删被引用的模块，或反过来，都会在这里变红。

运行时：无。被删的入口从未有过生产运行，没有可复现的运行时行为。
