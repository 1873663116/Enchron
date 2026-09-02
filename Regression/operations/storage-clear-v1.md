---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:storage.clear@1",
  "title": "Storage Clear",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "target",
        "type": "string",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "cache.state",
    "ui.navigation",
    "ui.state",
    "viewing.progress",
    "viewing.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:06733d4f3fc59b242183989211ccf4287b078265d302639a7c93077ae6df81ac"
  }
}
---
# Storage Clear

The runtime Operation adapter selects the Settings tab, opens the Storage & Privacy category and taps the named clear action in one tapSequence, then verifies from the viewing-storage probe that the named store is empty while protected library and playback settings state is unchanged. The call leaves the browsing ornament on the Settings tab inside that category, so it disturbs ui.navigation as well as the cleared store.
