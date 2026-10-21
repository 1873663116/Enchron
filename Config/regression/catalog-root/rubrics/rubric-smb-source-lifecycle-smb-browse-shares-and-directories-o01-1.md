---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:smb-source-lifecycle.smb-browse-shares-and-directories.o01@1",
  "title": "Smb Browse Shares And Directories",
  "criteria": [
    "The bound observation records stage 0 with empty pathComponents whose folder card names equal the hostShares set the host preflight enumerated from the server, no visible card name ending with '$', hostShareName present in that set and equal to requestedPathComponents[0], and facts.itemCount equal to facts.visibleCardCount.",
    "Every later stage has itemCount equal to visibleCardCount; stages[1].pathComponents is exactly [hostShareName]; the remaining requested path is TestVectors, Enchron, PlaybackBehavior; and the final stage includes a video card named expectedVideoName."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing hostShareName, hostShares, or expectedVideoName, a value that still starts with result://, a missing required stage, or a stale snapshot produces a non-passing result.",
    "An SMB root that omits any enumerated non-administrative share, or lists one the server did not offer, cannot Satisfy; a single expected share found among the cards is not evidence that the root lists the server's shares.",
    "An administrative share, stale item count, path skip, or WebDAV-style breadcrumb substituted for SMB violates the rubric."
  ]
}
---
# Smb Browse Shares And Directories

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
