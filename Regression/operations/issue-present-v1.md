---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:issue.present@1",
  "title": "Issue Present",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "category",
        "type": "string",
        "required": true
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "issue.surface",
    "playback.position",
    "playback.selection",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56"
  }
}
---
# Issue Present

The runtime Operation adapter maps each allowed issue category onto a closed remote-fault recipe (source-file-missing→missing-object, source-access-denied→access-denied, connection-interrupted→transport-interrupted, media-data-corrupt→corrupt-media, server-certificate-changed→certificate-rotation), opens the issue-fixture WebDAV media when window playback is not already live, activates that recipe, and waits until PlayerUI-window-control-plane error equals the category and the matching main-window action identifiers occupy the single issue slot. A second call restores any prior recipe, activates the next one, and uses Retry on an activePlaybackFailure without clearing the slot so the newest issue replaces it. Categories without an induce route are rejected. Diagnostic-bypass injection is not used.
