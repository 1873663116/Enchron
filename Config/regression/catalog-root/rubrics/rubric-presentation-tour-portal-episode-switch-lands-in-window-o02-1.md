---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.portal-episode-switch-lands-in-window.o02@1",
  "title": "Portal To Window Episode Switch Shows Pixels",
  "criteria": [
    "The producer requests exactly context window, count 3, minimumIntervalMillis 1000, and relatedResults naming call 07's response, where call 07 awaited the window window state right after the episode switch.",
    "The producer returns exactly three indexed frames; every frame has a content-bound screenshot attachment, presentation is window, lifecycle is Playing, error is none, and adjacent capture times differ by at least 1000 ms.",
    "No frame's screenshot is blank, pure-colour, or undecodable, and at least one frame's screenshotDigest differs from frame 0's; the regression this closes is a stale panoramic surface after switching to a flat episode from portal, so uniform blankness across all three frames fails the claim regardless of the reported lifecycle."
  ],
  "negativeControls": [
    "A capture taken before the episode-menu activation, fewer than three frames, or a sub-1000 ms interval is Indeterminate, not Satisfied.",
    "A blank, pure-colour or undecodable screenshot at any index, three identical screenshots, a non-Playing lifecycle, or a non-none error fails the bound case."
  ]
}
---
# Portal To Window Episode Switch Shows Pixels

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
