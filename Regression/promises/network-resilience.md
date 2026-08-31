---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "network-resilience",
  "title": "Network Resilience",
  "promises": [
    {
      "id": "promise:network-resilience:c01",
      "title": "解封装读线程把缓冲填至水位线，即使没有消费者在等待也继续填包。",
      "statement": "解封装读线程把缓冲填至水位线，即使没有消费者在等待也继续填包。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:network-resilience:c02",
      "title": "可恢复的读失败与真正的流结束被区分开，读失败之后可以恢复。",
      "statement": "可恢复的读失败与真正的流结束被区分开，读失败之后可以恢复。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:network-resilience:c03",
      "title": "断线后进行有限次的退避重连；播放引擎不主动断开连接。",
      "statement": "断线后进行有限次的退避重连；播放引擎不主动断开连接。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:network-resilience:c04",
      "title": "加载指示由播放饥饿触发，而不由网络事件触发；缓冲充足时，整个重连过程不出现任何提示。",
      "statement": "加载指示由播放饥饿触发，而不由网络事件触发；缓冲充足时，整个重连过程不出现任何提示。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:network-resilience:c05",
      "title": "播放中的失败分为四类：连接中断、文件不存在、拒绝访问、数据损坏；每一类都给出对应的下一步指引，并保住播放位置。",
      "statement": "播放中的失败分为四类：连接中断、文件不存在、拒绝访问、数据损坏；每一类都给出对应的下一步指引，并保住播放位置。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:network-resilience:c06",
      "title": "播放中的证书变更单独归为一类：此时停止播放，且不在此刻接受该证书。",
      "statement": "播放中的证书变更单独归为一类：此时停止播放，且不在此刻接受该证书。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Network Resilience promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:network-resilience:c01`

Proposal `PR-NR-C01` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 9, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:network-resilience:c02`

Proposal `PR-NR-C02` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 10, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:network-resilience:c03`

Proposal `PR-NR-C03` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 11, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:network-resilience:c04`

Proposal `PR-NR-C04` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 12, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:network-resilience:c05`

Proposal `PR-NR-C05` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 13, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:network-resilience:c06`

Proposal `PR-NR-C06` comes from `.agents/skills/vp-e2e/features/network-resilience.md` at line 14, section Sub-features, source ordinal 6.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
