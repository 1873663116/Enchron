---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.transition-timeout-rolls-back.o01@1",
  "title": "Transition Timeout Rolls Back",
  "criteria": [
    "After a real Enter Panorama action, the armed one-shot settlement-timeout fault is consumed and the named spatial-surface-settlement-failed path returns the product presentation, attachment, and renderer consumer to Portal.",
    "The terminal product state has transition and pendingSpatialEffect both none, lifecycle Playing, surfaceAttachmentFailed visible, presentationRolledBack recorded, one live and zero retiring technical sessions, and a present Portal renderer entity."
  ],
  "negativeControls": [
    "A controller-only success, an unconsumed fault, or a trace from another attempt is inadmissible.",
    "Panorama success, a generic presentationConversionFailed replacement, a pending transition, a non-Portal attachment, stopped playback, or any extra live or retiring technical session violates the rollback contract.",
    "The fault is DEBUG-only, typed, one-shot, and cleared when the trace is disarmed; no production behavior may depend on it."
  ]
}
---
# Transition Timeout Rolls Back

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
