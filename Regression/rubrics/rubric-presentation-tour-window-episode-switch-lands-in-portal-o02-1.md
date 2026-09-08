---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.window-episode-switch-lands-in-portal.o02@1",
  "title": "Window To Portal Episode Switch Shows Pixels",
  "criteria": [
    "The producer requests exactly context portal, count 3, minimumIntervalMillis 1000, and relatedResults naming call 07's response, where call 07 awaited the portal window state right after the episode switch.",
    "The producer returns exactly three indexed frames; every frame has a content-bound screenshot attachment, presentation is portal, lifecycle is Playing, error is none, and adjacent capture times differ by at least 1000 ms.",
    "No frame's screenshot is blank, pure-colour, or undecodable, and at least one frame's screenshotDigest differs from frame 0's; the regression this closes is a stale flat surface after switching to a panoramic episode from the window, so uniform blankness across all three frames fails the claim regardless of the reported lifecycle."
  ],
  "negativeControls": [
    "A capture taken before the episode-menu activation, fewer than three frames, or a sub-1000 ms interval is Indeterminate, not Satisfied.",
    "A blank, pure-colour or undecodable screenshot at any index, three identical screenshots, a non-Playing lifecycle, or a non-none error fails the bound case."
  ]
}
---
# Window To Portal Episode Switch Shows Pixels

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
