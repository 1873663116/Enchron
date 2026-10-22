---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-local-media-lifecycle-automatic-play-next-resume-policy@1",
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
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/viewing-storage-16m01s.mp4",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4"
        ],
        "target": "scenario-local-media-lifecycle-automatic-play-next-resume-policy"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-local-media-lifecycle-automatic-play-next-resume-policy",
          "entry": "root"
        }
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-local-media-lifecycle-automatic-play-next-resume-policy"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-settings"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-category-playback"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "Settings-menu-resume-strategy",
          "Settings-menuOption-resume-strategy-askEveryTime"
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "Settings-menu-end-behavior",
          "Settings-menuOption-end-behavior-playNext"
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "Settings-menu-controls-auto-hide",
          "Settings-menuOption-controls-auto-hide-never"
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-files"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "viewing-storage-16m01s.mp4"
        },
        "timeoutMs": 45000,
        "intervalMs": 400
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 20.0,
        "mode": "atLeast",
        "timeoutMs": 45000,
        "intervalMs": 400
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-files"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "resolveResumePrompt",
            "arguments": {
              "action": "resume"
            }
          },
          {
            "verb": "resolveResumePrompt",
            "arguments": {
              "action": "resume"
            }
          }
        ]
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 20.0,
        "mode": "atLeast",
        "timeoutMs": 45000,
        "intervalMs": 400
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-files"
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "sdr-bframe-multiaudio-avsync-30s.mp4"
        },
        "timeoutMs": 45000,
        "intervalMs": 400
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
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
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
        "probe": "PlayerUI-window-control-plane",
        "field": "lifecycle",
        "equals": "Playing",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 20.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
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
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "scenario-local-media-lifecycle-automatic-play-next-resume-policy"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  }
}
---

Ended Play Next resume policy

Generated from `Regression/journeys/local-media-lifecycle/scenarios/automatic-play-next-resume-policy.md`.
