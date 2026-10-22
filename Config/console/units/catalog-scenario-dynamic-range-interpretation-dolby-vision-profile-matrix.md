---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-dynamic-range-interpretation-dolby-vision-profile-matrix@1",
  "layer": 3,
  "role": "verification",
  "pace": "scenario",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
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
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/Profile7.6/FEL_test_for_AVS.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/HD/Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
          "test-media:Samples/DynamicRange/DolbyVision/Profile10/OfficialDolby/P10.0/media-video-dav1-dav1-1.mp4"
        ],
        "target": "scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
        }
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-dynamic-range-interpretation-dolby-vision-profile-matrix",
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
      "args": {
        "clean": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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
        "field": "mediaName",
        "equals": "Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
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
      "args": {
        "clean": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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
        "identifier": "MediaLibrary-grid-video-FEL_test_for_AVS.mp4"
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
        "field": "mediaName",
        "equals": "FEL_test_for_AVS.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
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
      "args": {
        "clean": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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
        "field": "mediaName",
        "equals": "Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
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
      "args": {
        "clean": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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
        "field": "mediaName",
        "equals": "Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
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
      "args": {
        "clean": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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
        "identifier": "MediaLibrary-grid-video-media-video-dav1-dav1-1.mp4"
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
        "field": "mediaName",
        "equals": "media-video-dav1-dav1-1.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
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
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "scenario-dynamic-range-interpretation-dolby-vision-profile-matrix"
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

Dolby Vision profile 5、7、8 与 10 处理矩阵

Generated from `Config/regression/catalog-root/journeys/dynamic-range-interpretation/scenarios/dolby-vision-profile-matrix.md`.
