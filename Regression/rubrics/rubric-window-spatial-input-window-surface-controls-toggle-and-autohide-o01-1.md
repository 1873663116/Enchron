---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:window-spatial-input.window-surface-controls-toggle-and-autohide.o01@1",
  "title": "Window Surface Controls Toggle And Autohide",
  "criteria": [
    "Three Device Hub gaze-and-pinch actions after the baseline produce exactly three accepted EnchronWindowInput.surface spatialTap events and ordered control visibility shown→hidden→shown while lifecycle remains Playing.",
    "The final probe waits 9000 ms after the third action; controls are then hidden under the exact 8000 ms product idle policy, proving the delivered interaction restarted the timer."
  ],
  "negativeControls": [
    "A duplicate import, toggleControls command, XCUITest-only tap return, missing or extra spatialTap, wrong visibility parity, non-Playing lifecycle, or controls still visible after 9000 ms fails the rubric."
  ]
}
---
# Window Surface Controls Toggle And Autohide

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
