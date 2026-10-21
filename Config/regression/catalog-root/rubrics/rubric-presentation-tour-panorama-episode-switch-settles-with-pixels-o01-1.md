---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.panorama-episode-switch-settles-with-pixels.o01@1",
  "title": "Panorama Episode Switch Settles With Pixels",
  "criteria": [
    "The producer requests exactly context panorama, count 3, minimumIntervalMillis 1000, and relatedResults naming call 09's matchedElement and response in that order, where call 09 read PlayerUI-spatial-state in context panorama with requireMatchedElement true right after selecting 360.mp4 from PlayerPanel-menu-more → PlayerPanel-menu-episodes.",
    "The producer returns exactly three indexed frames; every frame has a content-bound screenshot attachment, presentation is panorama, lifecycle is Playing, error is none, and adjacent capture times differ by at least 1000 ms.",
    "No frame's screenshot is blank, pure-colour, or undecodable, and at least one frame's screenshotDigest differs from frame 0's — the exact regression this closes is a black screen after switching episodes while in panorama, so uniform blankness across all three frames fails the claim regardless of the reported lifecycle."
  ],
  "negativeControls": [
    "A missing PlayerUI-spatial-state matchedElement, a capture taken before the episode-menu activation, fewer than three frames, or a sub-1000 ms interval is Indeterminate, not Satisfied.",
    "A blank, pure-colour or undecodable screenshot at any index, three identical screenshots, a non-Playing lifecycle, or a non-none error fails the bound case."
  ]
}
---
# Panorama Episode Switch Settles With Pixels

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
