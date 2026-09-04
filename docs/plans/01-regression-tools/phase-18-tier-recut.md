[← overview](overview.md)

# 阶段 18：path 到 tier 重切

## 目标

`Apps/Enchron/Screens/` 与 `Modules/MediaLibrary/` 归 W2。前者当前落在 `Apps/Enchron/` 的 W3，后者已经是 W2，本阶段把它在前缀表里显式写出并与前者一起在文档中说明理由。

## 改动清单

- `Scripts/rules/merge_evidence_tier.py`。`PATH_RULES`（:46-62）增一条 `("Apps/Enchron/Screens/", W2)`。前缀按最长匹配（`classify_path`，:86-93），因此 `Apps/Enchron/Screens/` 命中 W2 而 `Apps/Enchron/` 的其余路径仍是 W3，与 `Packages/PlaybackCore/Tests/` 落 W1 而包本体落 W3 是同一个机制。`Modules/MediaLibrary/` 的 W2 条目（:56）已存在，不动。
- `docs/MERGE_EVIDENCE.md`。「Tier 与路径分类」一节的前缀表（:28-34）增同一行。表下补一句说明最长前缀匹配对这一条的作用，与既有的 `Packages/PlaybackCore/Tests/` 说明并列。
- `Config/guard_selftests.json`。`merge-evidence-tier` 的坏样本补一条：一个 `Apps/Enchron/Screens/` 下的改动被判为 W3 时必须失败。

`docs/CONTEXT.md:39-48` 的 W0 到 W3 阶梯定义不变，本阶段只改路径到级别的映射，不改级别本身的含义。

## 数据结构与形态

```python
PATH_RULES: tuple[tuple[str, str], ...]
classify_path(path: str) -> Classification(path, tier, rule)
```

新增条目：

```text
("Apps/Enchron/Screens/", W2)
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/merge_evidence_tier.py --json
python3 Scripts/rules/verify_guard_selftests.py
python3 Scripts/rules/verify_documentation_references.py
```

运行时：

```sh
python3 Scripts/rules/merge_evidence_tier.py origin/main..HEAD --json
```

对一个只动 `Apps/Enchron/Screens/` 的 commit 范围跑分类器，`tier` 必须是 `W2`，`requiredEvidence` 为 `verification-green` 与 `simulator-e2e` 两项，不含 `device-hub-input`。同一命令对一个动 `Apps/Enchron/` 其他路径的范围仍返回 `W3`。这两次调用是最长前缀匹配生效的直接证明。它不需要设备。
