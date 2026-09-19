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
    "certificate.trust",
    "fixture.corpus",
    "issue.surface",
    "playback.position",
    "playback.selection",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "source.connection",
    "source.session",
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:ae8fea431404aff80dcaff8f682f2eed40133687ea79e4230c13a89dd346d832"
  }
}
---
# Issue Present

The runtime Operation adapter maps each allowed issue category onto a closed remote-fault recipe (source-file-missing→missing-object, source-access-denied→access-denied, connection-interrupted→transport-interrupted, media-data-corrupt→corrupt-media, server-certificate-changed→certificate-rotation), opens the issue-fixture WebDAV media when window playback is not already live, activates that recipe, and waits until PlayerUI-window-control-plane error equals the category and the matching main-window action identifiers occupy the single issue slot. A second call restores any prior recipe, activates the next one, and uses Retry on an activePlaybackFailure without clearing the slot so the newest issue replaces it. Categories without an induce route are rejected. Reaching that state selects the Enchron Regression WebDAV source and opens remote media, and every recipe is activated and restored through operation:host.preflight@1's remote-faults route, so this call disturbs the same certificate trust, fixture corpus and source connection and session state that Operation declares. Diagnostic-bypass injection is not used.
