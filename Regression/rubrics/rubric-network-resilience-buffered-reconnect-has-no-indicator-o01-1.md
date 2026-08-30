---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1",
  "title": "Buffered Reconnect Has No Indicator",
  "criteria": [
    "The paired-control attempt activates healthy and the fault attempt activates buffer-absorbed-interruption against the same registered WebDAV card; each exact receipt is restored before the bound producer completes.",
    "The bound artifact contains one three-frame paired-control sequence and one three-frame fault sequence. Its fault host trace contains an ordered successful Range 206 → injected 503 → recovered 206 sequence while the fault snapshots remain Playing, report buffer ahead > 0, expose neither loading nor issue surface, and have strictly increasing playback positions.",
    "Using the paired-control sequence's position deltas as the reference, every fault-sequence delta is at least 50% of the paired median delta and no fault interval exceeds 2000 ms without position advancement."
  ],
  "negativeControls": [
    "A fault receipt with no triggered read, a different media basename between attempts, an unrestored recipe, missing ordered host responses, or fewer than three product snapshots is inadmissible.",
    "Any visible loading/issue indicator, zero buffer-ahead, non-increasing fault position, or violation of the declared 50%/2000 ms tolerance fails the rubric."
  ]
}
---
# Buffered Reconnect Has No Indicator

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
