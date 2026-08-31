---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.portal-format-and-panorama-actions-coexist.o01@1",
  "title": "Portal Format And Panorama Actions Coexist",
  "criteria": [
    "The bound accessibility.tree is one portal tapSequence return (product.md:21) whose alsoInspected JSON array records, after afterStep label:Playback surface, PlayerUI-TopAction-resumePanorama and PlayerUI-TopAction-videoFormat as exists, enabled, and hittable in that same controller command. The producer declares dismissControls true, so the label:Playback surface step raises the portal chrome: the surface is a bare showControls.toggle() (PlaybackSessionModel.swift:579-589) and the cancelled editor above it leaves the chrome shown, so without that declaration the step would hide both siblings in the same command that is supposed to read them.",
    "tappedIdentifiers contain only PlayerUI-TopAction-resumePanorama; videoFormat appears in alsoInspected and not in tappedIdentifiers; the command succeeds and does not deliver the sibling action."
  ],
  "negativeControls": [
    "A later snapshot or inspect after panorama settlement cannot establish coexistence, because product.md:17 removes portal chrome from the hierarchy.",
    "A route reached only through a diagnostic injection cannot satisfy a user-path delivery criterion.",
    "alsoInspected missing either sibling, a videoFormat identifier in tappedIdentifiers, evidence from window rather than portal, or a snapshot --identifier of portal chrome cannot Satisfy."
  ]
}
---
# Portal Format And Panorama Actions Coexist

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
