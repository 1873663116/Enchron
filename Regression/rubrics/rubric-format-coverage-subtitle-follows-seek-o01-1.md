---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.subtitle-follows-seek.o01@1",
  "title": "Subtitle Follows Seek",
  "criteria": [
    "The structural-test artifact reports succeeded true with returnCode 0, and its check and command are the allowlisted pair registered for this case: subtitle-lane-seek runs swift test --package-path Packages/PlaybackCore --filter subtitleLaneCoversTheSeekTargetAfterASeek. The artifact's check is subtitle-lane-seek and the bound caseKey is seek.",
    "assertionPayloads holds exactly one object, and it alone decides the behaviour. Its assertion is subtitle-follows-seek and its check equals the artifact's own check, so the payload belongs to this run. seekTargetSeconds parses as a number greater than zero, cueCount is at least one, and cueText is not empty. Together they state that a subtitle cue covered a time after the seek target once the seek completed."
  ],
  "negativeControls": [
    "A passing test for another subtitle behaviour cannot satisfy this case.",
    "A compile-only result, a zero-test selection, or a structural artifact whose command differs from the allowlisted command cannot satisfy the rubric.",
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric, and neither can more or fewer than one payload. A cueCount of zero, an empty cueText, or a seekTargetSeconds that is not a positive number violates the commitment."
  ]
}
---
# Subtitle Follows Seek

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
