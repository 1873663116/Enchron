---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.finite-backoff-reconnect.o01@1",
  "title": "Finite Backoff Reconnect",
  "criteria": [
    "The application trace records no more than three demux reconnect attempts with reviewed 250, 500 and 1000 millisecond backoff ordering.",
    "Source-side connection closure is attributable to the injected upstream fault or exhausted recovery, never an unsolicited playback-engine disconnect."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Unlimited retries, missing a declared backoff, a byte-stream retry layer, or engine-originated disconnect violates the rubric."
  ]
}
---
# Finite Backoff Reconnect

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
