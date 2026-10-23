---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-local-media-lifecycle-external-subtitle-source-matrix.part2@1",
  "layer": 3,
  "role": "verification",
  "pace": "catalog",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
  "isolation": "clean-library",
  "preconditions": [
    {
      "kind": "media-server",
      "provider": "emby"
    },
    {
      "kind": "media-source",
      "provider": "webdav"
    }
  ],
  "actions": [
    {
      "verb": "device.session.ensure",
      "args": {
        "lane": "simulator"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetState",
        "arguments": {
          "keepSession": "true"
        }
      }
    },
    {
      "verb": "device.connect-source",
      "args": {
        "provider": "webdav",
        "name": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.zh-CN.srt",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.styled.ass"
        ],
        "target": "."
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importMediaDirectory",
        "arguments": {
          "directory": "sdr-bframe-aggregate-30s-sidecars",
          "media": "sdr-bframe-aggregate-30s.mkv",
          "files": "[\"sdr-bframe-aggregate-30s.mkv\", \"sdr-bframe-aggregate-30s.zh-CN.srt\", \"sdr-bframe-aggregate-30s.styled.ass\"]"
        }
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetState",
        "arguments": {
          "keepSession": "true"
        }
      }
    },
    {
      "verb": "device.connect-source",
      "args": {
        "provider": "webdav",
        "name": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFiles",
        "arguments": {
          "directory": "scenario-local-media-lifecycle-external-subtitle-source-matrix"
        }
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.zh-CN.srt",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.styled.ass"
        ],
        "target": "."
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "importMediaDirectory",
            "arguments": {
              "directory": "sdr-bframe-aggregate-30s-sidecars",
              "media": "sdr-bframe-aggregate-30s.mkv",
              "files": "[\"sdr-bframe-aggregate-30s.mkv\", \"sdr-bframe-aggregate-30s.zh-CN.srt\", \"sdr-bframe-aggregate-30s.styled.ass\"]"
            }
          },
          {
            "verb": "resetMediaNavigation",
            "arguments": {}
          }
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Navigation-Tab"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Sidebar-home"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Emby"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Series, poster",
        "labelPrefix": "Enchron Regression Series"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Episode-",
        "identifierPrefix": "Emby-Episode-",
        "waitMilliseconds": 1200
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "presentation",
        "equals": "window",
        "timeoutMs": 45000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "toggleControls",
        "arguments": {
          "visible": "true"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "PlayerUI-TopAction-more",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-TopAction-more"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "PlayerUI-menu-subtitles",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-menu-subtitles"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "label",
        "equals": "English (SRT)",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "English (SRT)"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "subtitleTrack",
        "mode": "differs",
        "equals": "off",
        "timeoutMs": 30000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "subtitleCues",
        "mode": "atLeast",
        "equals": 1,
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 1,
        "intervalMs": 1000
      }
    }
  ],
  "teardown": [
    {
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "frames.json",
    "schema": "enchron.console.frames@1"
  }
}
---

本地、远程与 Emby 外挂字幕加载

Generated from `Regression/journeys/local-media-lifecycle/scenarios/external-subtitle-source-matrix.md`.
