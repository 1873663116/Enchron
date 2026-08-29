---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.progress-authority-server.o01@1",
  "title": "Progress Authority Server",
  "criteria": [
    "The server reports an active session and advancing position for the opened item, then records the exit position within the reviewed tolerance.",
    "No corresponding local viewing-state record exists for the Emby media identity."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "Product-only progress without server state, server progress for another user or item, or a local fallback record violates the rubric."
  ]
}
---
# Progress Authority Server

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
