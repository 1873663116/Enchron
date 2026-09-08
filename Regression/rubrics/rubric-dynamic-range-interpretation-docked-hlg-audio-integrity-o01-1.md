---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.docked-hlg-audio-integrity.o01@1",
  "title": "Docked HLG Audio Renderer Stays Healthy",
  "criteria": [
    "Call 08's fields.audioRendererError equals none (MainView.swift:974, `audioRendererError=\\(output.audioRendererError ?? \"none\")`), read from the docked-resident PlayerUI-playback-state snapshot taken right after presentation.enter-docked-skybox@1 and the harness.assert-channels@2 gate.",
    "Call 08's fields.audioRendererSamples (MainView.swift:969, `audioRendererSamples=\\(output.audioRendererSamples)`) is strictly greater than call 05's pre-docked baseline value referenced via relatedResults, and fields.hasAudio (MainView.swift:967) remains true — the exact regression this closes is audio going silent right after entering docked while the picture keeps playing.",
    "session (MainView.swift:927) and lifecycle (MainView.swift:926) are unchanged between call 05 and call 08, so the two readings are bound to the same playback attempt rather than a relaunch."
  ],
  "negativeControls": [
    "A missing PlayerUI-playback-state read, a changed session between call 05 and call 08, or an absent audioRendererSamples/audioRendererError field is Indeterminate, not Satisfied.",
    "A non-none audioRendererError, a non-advancing or unavailable audioRendererSamples count, or hasAudio false fails the bound case."
  ]
}
---
# Docked HLG Audio Renderer Stays Healthy

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
