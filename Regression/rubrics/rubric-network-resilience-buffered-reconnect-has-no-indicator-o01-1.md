---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1",
  "title": "Buffered Reconnect Has No Indicator",
  "criteria": [
    "For caseKey paired-control, the bound artifact is the three-frame healthy control sequence for the registered WebDAV card after its exact activation receipt is restored; the frames remain Playing with increasing positions and expose no loading or issue surface.",
    "For caseKey buffer-absorbed-interruption, the bound artifact is the three-frame fault sequence for the same registered WebDAV card; its exact receipt is restored, its host trace contains ordered successful Range 206, injected 503, and recovered 206 responses, and the frames remain Playing with buffer ahead greater than zero, increasing positions, and no loading or issue surface."
  ],
  "negativeControls": [
    "A mismatched case, unrestored recipe, missing ordered host responses for the fault case, fewer than three product snapshots, a visible loading or issue indicator, zero buffer-ahead, or a non-increasing position fails the bound case."
  ]
}
---
# Buffered Reconnect Has No Indicator

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
