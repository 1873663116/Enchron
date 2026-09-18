---
{
  "schema": "enchron.regression.promises",
  "schemaVersion": 1,
  "feature": "playback-queue",
  "title": "Playback queue",
  "promises": [
    {
      "id": "promise:playback-queue:c01",
      "title": "Ended Play Next resume policy",
      "statement": "The ended-state Play Next affordance continues from the stored position according to the queue action without an Ask Every Time resume prompt; reaching end of media never launches the next item by itself.",
      "automation": {
        "scope": "included"
      }
    }
  ]
}
---
# Playback queue

These commitments are included in unattended Regression Catalog v2 coverage.
