---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.prefetch-without-waiting-consumer.o01@1",
  "title": "Prefetch Without Waiting Consumer",
  "criteria": [
    "The reviewed runtime trace shows the demux reader advancing subscribed queues toward the configured forward byte limit while no consumer is blocked waiting.",
    "The queue stops once forwardBufferedBytes reaches that configured limit, rather than reading the entire source or stalling after the first packet."
  ],
  "negativeControls": [
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric.",
    "Missing source identity, fixture digest, or compared field produces Indeterminate rather than Satisfied.",
    "A trace produced only while a consumer waits, an unbounded read, or a queue that never approaches the configured byte limit violates the rubric."
  ]
}
---
# Prefetch Without Waiting Consumer

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
