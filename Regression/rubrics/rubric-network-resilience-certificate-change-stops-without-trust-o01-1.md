---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:network-resilience.certificate-change-stops-without-trust.o01@1",
  "title": "Certificate Change Stops Without Trust",
  "criteria": [
    "Rotating the active HTTPS source certificate interrupts the existing TLS connection; the application records exactly one matching previous/new fingerprint pair, pauses the active session, and presents server-certificate-changed.",
    "The only delivered issue action is Close. Closing stops the session, no playback trust prompt or decision occurs, and the stored fingerprint remains the previous value while the rotated fingerprint remains untrusted."
  ],
  "negativeControls": [
    "A controller receipt without the application certificateBoundary delivery and matching fingerprint pair is inadmissible.",
    "Continuing playback, a generic issue, any action other than Close, an active session after Close, or any playback promptRequested, promptPresented, or decision event violates the interruption contract.",
    "Replacing the stored fingerprint with the rotated fingerprint, accepting the new certificate, or losing the post-Close trust probe violates the trust-boundary contract."
  ]
}
---
# Certificate Change Stops Without Trust

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
