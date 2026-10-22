---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch@1",
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
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
        ],
        "target": "scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch",
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
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch"
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
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
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
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-apply"
        ]
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
        "intervalMs": 1000
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
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch"
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
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
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
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-apply"
        ]
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
        "intervalMs": 1000
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
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch"
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
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
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
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-cancel"
        ]
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
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
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "scenario-dynamic-range-interpretation-dolby-vision-cross-compatibility-switch"
        }
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

兼容 Dolby Vision 在 HDR10 或 HLG 解释间切换

Generated from `Regression/journeys/dynamic-range-interpretation/scenarios/dolby-vision-cross-compatibility-switch.md`.
