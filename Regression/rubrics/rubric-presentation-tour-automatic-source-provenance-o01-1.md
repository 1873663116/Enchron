---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.automatic-source-provenance.o01@1",
  "title": "Automatic Source Provenance",
  "criteria": [
    "The initial internal-apple-apmp-180-v1 snapshot reports the reviewed half-equirectangular source declaration; a Flat override changes only the effective user format and revision, not that source declaration.",
    "One surface→videoFormat→automatic→apply accessibility transaction resets the override, after which the bound playback state reports source provenance and the exact original projection/stereo values."
  ],
  "negativeControls": [
    "Opening the editor without summoning controls, splitting one transient editor selection across controllers, mutating source declaration, leaving user provenance after Apply, or observing only UI selection without effective-format change fails the rubric.",
    "Using un-signalled 360.mp4 as a source-provenance oracle is inadmissible."
  ]
}
---
# Automatic Source Provenance

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
