---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1",
  "title": "Format Editor Hosts Window And Portal",
  "criteria": [
    "The bound case delivers the editor transaction registered for its host, read from the producer's own relatedResults. Window inlines relatedResults[0..1], the surface→PlayerUI-TopAction-videoFormat→PlayerUI-VideoFormat-cancel transaction, and relatedResults[2..3], the second surface→PlayerUI-TopAction-videoFormat sequence. Portal inlines relatedResults[0], the Playback surface label activation, relatedResults[1..2], the compact videoFormat→cancel sequence, and relatedResults[3], the Playback surface label activation that immediately precedes the bound activation. Each inlined response succeeded and names its own tapped identifiers or label.",
    "The window case binds the editor hierarchy and registered values from its own matchedElement. The portal case binds its own successful videoFormat activation together with the inlined Playback surface activation responses, including the matched public elements that live outside the main-window hierarchy and are therefore evidenced by each activation's own return rather than by hierarchy text."
  ],
  "negativeControls": [
    "Addressing a window-only surface identifier from portal, splitting one transient sheet action across controllers, inspecting only element existence, reading a transaction that the producer does not inline through relatedResults, or using a diagnostic injection route cannot satisfy either host case."
  ]
}
---
# Format Editor Hosts Window And Portal

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
