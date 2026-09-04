[← overview](overview.md)

# 阶段 1：注释规则扩到 Scripts 与存量清零

## 目标

`Scripts/**/*.py` 与产品 Swift 源码适用同一条注释禁令，存量注释清零。本阶段已在本 PR 完成：`python3 Scripts/rules/verify_product_source_comments.py` 报「182 product Swift files and 263 harness Python files contain no source comments」并以 0 退出。

## 改动清单

- `Scripts/rules/verify_product_source_comments.py`（本 PR 已完成）。原来的 `SOURCE_ROOTS` 拆成 `SWIFT_ROOTS`（`Apps/Enchron`、`Modules`、`Packages/PlaybackCore/Sources`）与 `PYTHON_ROOTS`（`Scripts`）。新增 `python_comments()`，用标准库 `tokenize` 取 `COMMENT` token，跳过第一行的 shebang，`TokenError` 与 `SyntaxError` 记为 `untokenizable source` 一条违规而不是静默放行。用 `tokenize` 而不是正则，因为 `#` 出现在字符串字面量里不是注释。
- `Scripts/rules/test_product_source_comments.py`（本 PR 已完成）。补 Python 分支的正负样本：字符串中的 `#`、行内注释、文档字符串、shebang。
- `Config/guard_selftests.json`（本 PR 已完成）。为 `product-source-comments` 增一条 Python 坏样本，满足 `docs/CONTEXT.md` 的 Mutation Coverage Mandate。
- 存量清零（本 PR 已完成）。设计定稿时 307 条，规则扩容后实测 289 条，分布为 `Scripts/regression/` 22、`Scripts/rules/` 116、`Scripts/verification/` 151，已全部清空。每条注释的去向由检查器自己的失败文案规定：外部约束移入所属 constraints 文档，实测值改为具名常量，不变式改写为类型或检查。

## 数据结构与形态

```python
Comment(line: int, column: int, token: str)
python_comments(source: str) -> tuple[Comment, ...]
```

## 阶段验证方案

静态：

```sh
python3 Scripts/rules/run_verification.py --quick
python3 Scripts/rules/test_product_source_comments.py
python3 Scripts/rules/verify_product_source_comments.py
```

第三条命令必须零输出零退出码，这是本阶段的完成判据。

运行时：无。本阶段只改源码文本与检查器，设备侧没有可证的行为变化。
