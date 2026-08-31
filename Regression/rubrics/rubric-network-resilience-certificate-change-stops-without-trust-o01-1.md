---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.certificate-change-stops-without-trust.o01@1",
  "title": "Certificate Change Stops Without Trust",
  "criteria": [
    "operationOutput.certificateChangeObservation records exactly one certificateBoundary changed previous/new fingerprint pair that matches remoteObservation.priorCertificateFingerprint and certificateFingerprint; relatedResults[0] is the pre-Close window control-plane fields with lifecycle=Paused, error=server-certificate-changed, and active=true.",
    "The only delivered issue action is Close. certificateChangeObservation.deliveredCloseEvents is nonempty, playbackPromptEvents is empty, afterClose or the bound playbackObservation shows the session stopped (active=false and session=none, or the post-Close playback-state probe unavailable), storedFingerprintAfterClose equals the previous fingerprint, and currentFingerprintTrustedAfterClose is false. The post-Close certificateTrustProbe payload (schema enchron.regression.certificate-trust-probe@1) is the trust mapping that observation inlined."
  ],
  "negativeControls": [
    "A controller receipt without the application certificateBoundary delivery and matching fingerprint pair is inadmissible.",
    "Continuing playback, a generic issue, any action other than Close, an active session after Close, or any playback promptRequested, promptPresented, or decision event violates the interruption contract.",
    "Replacing the stored fingerprint with the rotated fingerprint, accepting the new certificate, or losing the post-Close trust probe violates the trust-boundary contract. Host remoteObservation priorCertificateFingerprint/certificateFingerprint are server certificates and cannot establish storedFingerprintAfterClose."
  ]
}
---
# Certificate Change Stops Without Trust

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
