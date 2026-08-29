---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1",
  "title": "Source Failure Guidance Matrix",
  "criteria": [
    "The four independent attempts differ by one exact boundary input: valid address/user with wrong password → credentials-rejected; unreachableAddress → server-unreachable; missingPathAddress → invalid-address; and httpAddress → requires-https.",
    "Each attempt uses the same sourceMore→Add→WebDAV route, leaves the WebDAV form editable, preserves the entered non-secret draft values, exposes exactly the case-specific title/message/action set, and creates no source row."
  ],
  "negativeControls": [
    "Wrong username is not evidence of host unreachability, and an absolute result:// string typed literally is not evidence of invalid-address or requires-https handling.",
    "A generic message shared by the four cases, a created source row, a dismissed form, secret leakage, or controller output without the bound post-state fails the rubric."
  ]
}
---
# Source Failure Guidance Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
