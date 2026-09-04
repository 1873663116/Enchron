[← overview](overview.md)

# 阶段 5：删批量 campaign 启动入口

## 目标

删掉按 segment plan 并发拉起多个 lane 进程的启动器。它没有生产消费者。

## 改动清单

- 删 `Scripts/verification/run_campaign.py`（83 行）。唯一导入 `harness.campaign` 的生产文件。
- 删 `Scripts/rules/test_campaign_launcher.py`（186 行）。它是 `run_campaign.py` 的唯一消费者，:104、:156、:172 三处导入 `harness.campaign`。
- 删 `Scripts/verification/harness/campaign.py`。导出 `CampaignNotParallelizable`、`default_spawn`、`launch`、`segment_command`。上面两个文件删除后无导入方。

`Scripts/verification/harness/parallel.py` 保留。它持有 campaign 形状拒绝逻辑（:78-113），被 `Scripts/verification/reachability_matrix.py:8125` 的 `_campaign_serial_refusal` 方法使用。`harness/campaign.py` 不是它的另一份实现，而是它的调用方（`campaign.py:11-12` 导入 `parallel` 与 `CAMPAIGN_TOKEN_ENV`，:84-85 调 `parallel.lane_targets` 与 `parallel.partition_by_target`），依赖是单向的 campaign → parallel，所以删调用方不影响被调方。

删调用方牵动两处，本阶段一并处理：

- `serial_refusal_reason`（`parallel.py:106`）原文让操作者「run concurrently through the campaign launcher」并「Launch the campaign」，启动器删掉后这句指向不存在的工具。改为说明真实可走的路径：两条 lane 各自在自己的 worktree 里并发跑，由驱动并发的人设置 `ENCHRON_CAMPAIGN_TOKEN`。
- `campaign.py` 的 `default_spawn` 是全仓库唯一写 `ENCHRON_CAMPAIGN_TOKEN` 的地方。删除后该变量只剩定义（`parallel.py:5`）与读取（`reachability_matrix.py:8145`），没有生产者。拒绝逻辑保留不变，逃生门改为操作者手动导出该变量——新文案已写明。`campaign.json` 本就无仓内生产者（只在 `reachability_matrix.py:8135` 被读取），删启动器没有改变这一点。

`Scripts/verification/harness/lane_partition.py` 同样保留，`generate_reachability_segment_plan.py:46` 与 `reachability_matrix.py:36` 都依赖它。

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
