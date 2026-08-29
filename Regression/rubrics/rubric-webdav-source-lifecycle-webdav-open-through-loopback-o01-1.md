---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:webdav-source-lifecycle.webdav-open-through-loopback.o01@1",
  "title": "Webdav Open Through Loopback",
  "criteria": [
    "The selected remote card reaches lifecycle=Playing with a loopback PlaybackAddress while the remote source identity remains WebDAV.",
    "Valid time-separated frames contain changing real content and the server trace records range traffic rather than a naked URL crossing the playback boundary."
  ],
  "negativeControls": [
    "If any required modality is invalid or missing, the result is Indeterminate rather than inferred from the remaining modality.",
    "Contradictory valid artifacts produce Indeterminate; no majority vote or best-effort selection is permitted.",
    "Direct network URL exposure to playback, black or frozen frames, or a source identity change violates the rubric."
  ]
}
---
# Webdav Open Through Loopback

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
