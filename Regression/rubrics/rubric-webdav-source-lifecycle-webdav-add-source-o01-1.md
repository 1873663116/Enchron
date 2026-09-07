---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:webdav-source-lifecycle.webdav-add-source.o01@1",
  "title": "Webdav Add Source",
  "criteria": [
    "relatedResults[0] is call 06's alsoInspected trace: one resident tapSequence whose afterStep values are FileBrowsing-SourcesSidebar-sourceMore, then FileBrowsing-SourcesSidebar-addWebDAV in that order, with FileBrowsing-SourceConnection-webDAV-name exists=false after the first step and exists=true only after addWebDAV, so the form opens at the end of that single transaction and no field could be typed before it.",
    "relatedResults[1] and relatedResults[2] are call 11's alsoInspected and identifierResponse: one succeeded tapSequence whose afterStep values are FileBrowsing-SourceConnection-webDAV-connect then FileBrowsing-CertificateTrust-trust in that order, with FileBrowsing-CertificateTrust-trust exists=false after the trust step; relatedResults[3] is call 12's 以后 label tap reporting success; relatedResults[4] is call 13's interactionTrace measured from the call 05 baseline cursor and contains reachability files delivered action=sidebar.add.webDAV, reachability files delivered action=sourceConnection.webDAV.connect, and certificateBoundary decision approved=true, so the product delivered both activations rather than the controller merely reporting them; and the bound accessibility tree returns FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv as matchedElement with the registered WebDAV source present in its hierarchy."
  ],
  "negativeControls": [
    "Opening addWebDAV directly, splitting the source-menu route across controllers, or leaving the 以后 prompt unresolved is not the declared user route.",
    "A controller-only success — succeeded tapSequence responses with no matching product delivery line in the bound interactionTrace — a source created by direct state injection, an absent or null matchedElement, or a password value echoed in evidence cannot satisfy the rubric."
  ]
}
---
# Webdav Add Source

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
