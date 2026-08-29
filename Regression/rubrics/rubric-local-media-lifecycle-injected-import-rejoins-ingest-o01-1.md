---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.injected-import-rejoins-ingest.o01@1",
  "title": "Injected Import Rejoins Ingest",
  "criteria": [
    "The registered direct-child import command succeeds and its returned library snapshot contains exactly one reference with the expected file name."
  ],
  "negativeControls": [
    "A rejected direct child, accepted traversal path, missing reference, duplicate reference, or different file name violates the import-command contract."
  ]
}
---
# Injected Import Rejoins Ingest

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
