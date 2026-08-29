---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1",
  "title": "Track Selection Survives Seek And Presentation",
  "criteria": [
    "Every attempt opens registered WebDAV sdr-bframe-aggregate-30s.mkv, selects audio stream index 2 (FLAC 660 Hz) through More→Audio, and selects the automatically associated sdr-bframe-aggregate-30s.zh-CN.srt through More→Subtitles in two complete resident menu transactions.",
    "The bound post-mutation state preserves the same media identity and selected audio/subtitle track identities after seek, docked round trip, portal/window format round trip, or one format replacement; pure spatial transition cases also preserve the media session identity."
  ],
  "negativeControls": [
    "The nonexistent Commentary or external-reference identifiers, a same-label/different-ID fallback, split nested-menu controllers, selection loss, or session replacement during the docked pure transition fails the rubric."
  ]
}
---
# Track Selection Survives Seek And Presentation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
