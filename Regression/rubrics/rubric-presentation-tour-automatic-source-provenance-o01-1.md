---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.automatic-source-provenance.o01@1",
  "title": "Automatic Source Provenance",
  "criteria": [
    "relatedResults[0] is format.apply before (internal-apple-apmp-180-v1 source declaration) and relatedResults[1] is format.apply after the Flat override; after.fields.formatProvenance is userOverride while the source projection/stereo declaration in before.fields is unchanged.",
    "relatedResults[2] is one surface→PlayerUI-TopAction-videoFormat→PlayerUI-VideoFormat-automatic→PlayerUI-VideoFormat-apply transaction, and the bound window control-plane fields, sampled after that transient editor settles, are non-empty and report formatProvenance source with projection, stereoLayout and horizontalFieldOfViewDegrees equal to the source declaration in relatedResults[0].fields. The Flat override recorded in relatedResults[1].fields has therefore left the effective format and not merely the editor's selection. projection, stereoLayout and formatProvenance are assembled into PlayerUI-window-control-plane alone (Apps/Enchron/MainView.swift:752, :777 and :754); the playback-state string behind PlayerUI-playback-state (:1031-1154) republishes horizontalFieldOfViewDegrees at :1098 and carries none of the other three, so a playback probe can witness at most the field of view, can decide neither the projection and stereo declaration this criterion compares nor the provenance it reads, and evidence from one is inadmissible here."
  ],
  "negativeControls": [
    "Opening the editor without summoning controls, splitting one transient editor selection across controllers, mutating source declaration, leaving user provenance after Apply, or observing only UI selection without effective-format change fails the rubric.",
    "Using un-signalled 360.mp4 as a source-provenance oracle is inadmissible."
  ]
}
---
# Automatic Source Provenance

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
