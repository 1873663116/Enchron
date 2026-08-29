---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "cache-and-artwork",
  "title": "Cache And Artwork",
  "promises": [
    {
      "id": "promise:cache-and-artwork:c01",
      "title": "Container Index Cache：当远程来源第二次打开同一个文件时，容器索引不再走网络读取。",
      "statement": "Container Index Cache：当远程来源第二次打开同一个文件时，容器索引不再走网络读取。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:cache-and-artwork:c02",
      "title": "只有远程来源会写入索引缓存，本地播放不会写入。",
      "statement": "只有远程来源会写入索引缓存，本地播放不会写入。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:cache-and-artwork:c03",
      "title": "Artwork 在用户退出播放时从当前显示的画面捕获，新画面覆盖旧画面，整个过程不产生额外的读取。",
      "statement": "Artwork 在用户退出播放时从当前显示的画面捕获，新画面覆盖旧画面，整个过程不产生额外的读取。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:cache-and-artwork:c04",
      "title": "Emby 的封面走服务器的图片接口获取，以 image tag 作为键，不经过回环端点。",
      "statement": "Emby 的封面走服务器的图片接口获取，以 image tag 作为键，不经过回环端点。",
      "automation": {
        "scope": "included"
      }
    },
    {
      "id": "promise:cache-and-artwork:c05",
      "title": "设置页中有两行条目，分别显示各自的用量并提供清除操作。",
      "statement": "设置页中有两行条目，分别显示各自的用量并提供清除操作。",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Cache And Artwork promises

Every commitment in this feature is included in unattended Regression Catalog v1 coverage.

## Source traceability

### `promise:cache-and-artwork:c01`

Proposal `PR-CA-C01` comes from `.agents/skills/vp-e2e/features/cache-and-artwork.md` at line 7, section Sub-features, source ordinal 1.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:cache-and-artwork:c02`

Proposal `PR-CA-C02` comes from `.agents/skills/vp-e2e/features/cache-and-artwork.md` at line 8, section Sub-features, source ordinal 2.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:cache-and-artwork:c03`

Proposal `PR-CA-C03` comes from `.agents/skills/vp-e2e/features/cache-and-artwork.md` at line 9, section Sub-features, source ordinal 3.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:cache-and-artwork:c04`

Proposal `PR-CA-C04` comes from `.agents/skills/vp-e2e/features/cache-and-artwork.md` at line 10, section Sub-features, source ordinal 4.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.

### `promise:cache-and-artwork:c05`

Proposal `PR-CA-C05` comes from `.agents/skills/vp-e2e/features/cache-and-artwork.md` at line 11, section Sub-features, source ordinal 5.

The Promise covers only the commitment stated in front matter. Scenario evidence for another commitment cannot substitute for it.
