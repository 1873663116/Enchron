---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "remote-source-connection",
  "title": "Remote Source Connection",
  "promises": [
    {
      "id": "promise:remote-source-connection:c01",
      "title": "添加来源。路径是 More → Add → 选择类型 → 填写地址与凭据 → Connect。",
      "statement": "添加来源。路径是 More → Add → 选择类型 → 填写地址与凭据 → Connect。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:remote-source-connection:c02",
      "title": "浏览。共享或目录逐层展开，其中的视频以网格卡片呈现。",
      "statement": "浏览。共享或目录逐层展开，其中的视频以网格卡片呈现。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:remote-source-connection:c03",
      "title": "打开播放。点击远程卡片进入播放器，字节经回环端点传输。",
      "statement": "打开播放。点击远程卡片进入播放器，字节经回环端点传输。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:remote-source-connection:c04",
      "title": "凭据失败、找不到服务器、地址格式错误这几类失败各自给出可区分的下一步提示。",
      "statement": "凭据失败、找不到服务器、地址格式错误这几类失败各自给出可区分的下一步提示。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:remote-source-connection:c05",
      "title": "当证书无法验证时，App 在连接阶段弹出询问，展示地址、证书名、指纹与有效期；在播放阶段永远不会弹出询问。",
      "statement": "当证书无法验证时，App 在连接阶段弹出询问，展示地址、证书名、指纹与有效期；在播放阶段永远不会弹出询问。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Remote Source Connection promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:remote-source-connection:c01`

Proposal `PR-RSC-C01` comes from `.agents/skills/vp-e2e/features/remote-source-connection.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:remote-source-connection:c02`

Proposal `PR-RSC-C02` comes from `.agents/skills/vp-e2e/features/remote-source-connection.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:remote-source-connection:c03`

Proposal `PR-RSC-C03` comes from `.agents/skills/vp-e2e/features/remote-source-connection.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:remote-source-connection:c04`

Proposal `PR-RSC-C04` comes from `.agents/skills/vp-e2e/features/remote-source-connection.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:remote-source-connection:c05`

Proposal `PR-RSC-C05` comes from `.agents/skills/vp-e2e/features/remote-source-connection.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
