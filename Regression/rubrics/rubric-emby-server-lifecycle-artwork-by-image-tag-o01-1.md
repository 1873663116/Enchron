---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.artwork-by-image-tag.o01@1",
  "title": "Artwork By Image Tag",
  "criteria": [
    "The image request uses the server image endpoint and the persisted cache key includes the server-provided image tag.",
    "A changed image tag produces a distinct cache identity; directory content and viewing progress remain absent from local storage."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing source identity, fixture digest, or compared field produces Indeterminate rather than Satisfied.",
    "A loopback media endpoint request, item-id-only cache key, or stale reuse across tag changes violates the rubric."
  ]
}
---
# Artwork By Image Tag

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
