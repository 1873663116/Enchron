---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:smb-source-lifecycle.smb-browse-shares-and-directories.o01@1",
  "title": "Smb Browse Shares And Directories",
  "criteria": [
    "The SMB root lists the host-discovered non-administrative shares and excludes shares whose names end in dollar.",
    "At every path component, the product item count equals the exposed folders and media cards, and the target video card appears at the final path."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "An administrative share, stale item count, path skip, or WebDAV-style breadcrumb substituted for SMB violates the rubric."
  ]
}
---
# Smb Browse Shares And Directories

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
