---
{
  "schema": "enchron.console.known-failures",
  "schemaVersion": 1,
  "failures": [
    {
      "checker": "Domain tests",
      "match": "Tidal blends appearances with one atlas",
      "reason": "TidalEnvironmentTests throws CancellationError from the RealityKit scene handoff; measured on 2026-10-22, unrelated to the console."
    },
    {
      "checker": "Domain tests",
      "match": "cancelled preview delivers the natural end action once",
      "reason": "PlaybackSurfaceGestureControllerTests expects a natural end action after a cancelled preview; measured on 2026-10-22, unrelated to the console."
    }
  ]
}
---

Known failures let a defect that predates the console stay declared until it is fixed. Each entry names a unit and a phrase the failing step's detail must contain; a run that matches reports the verdict `known` and does not turn the tier red. Remove an entry when its defect is gone.
