---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.emby-artwork-bypasses-loopback.o01@1",
  "title": "Emby Artwork Bypasses Loopback",
  "criteria": [
    "The artwork network trace targets the Emby image API with the reviewed image tag and never targets the playback loopback endpoint.",
    "The resulting card image binds to the same Emby item and tag recorded in the cache state."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing source identity, fixture digest, or compared field produces Indeterminate rather than Satisfied.",
    "Any loopback artwork request, missing tag, or artwork bound to a different item violates the rubric."
  ]
}
---
# Emby Artwork Bypasses Loopback

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
