---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:issue-surface-behavior.source-failure-guidance-matrix.o01@1",
  "title": "Source Failure Guidance Matrix",
  "criteria": [
    "relatedResults[0] is the ordered route FileBrowsing-SourcesSidebar-sourceMore, -add, -addWebDAV, and relatedResults[1] and [2] are the post-action hierarchies in which the address and username fields hold the boundary input this case registers and this artifact can actually read: for credentials-rejected the registered valid address and the registered valid username, the pair that makes the rejection a credential rejection rather than a host or address fault -- its wrong password is typed with secret true and is redacted out of every post-action state by design, so no criterion asks to see it and criterion 2's credential-class message is what separates this case; unreachableAddress for server-unreachable; missingPathAddress for invalid-address; and httpAddress for requires-https.",
    "The matched FileBrowsing-SourceConnection-webDAV-error element is one combined status line (ConnectionFormPanel.swift:288-302 hides its icon and combines its children), so its label is the whole witness: it is the message RemoteConnectionFailure registers for this case (ConnectionFormPanel.swift:366-377), it names the corrective step that case calls for -- check the username and password, check the address and network, check the server address, or add https:// -- it is distinct from the other three cases' messages, and it repeats no typed credential.",
    "In the same response hierarchy the WebDAV form is still presented and editable -- FileBrowsing-SourceConnection-webDAV-name, -address, -username and -connect are present and enabled, the non-secret drafts still hold the values relatedResults[1] and [2] delivered, and the password field shows no plaintext -- and the sources sidebar holds no row for this attempt's name. That the form survived the connect is itself the reading that no certificate handoff intervened: a trust prompt dismisses this sheet before it appears, through the dismiss closure FilesScreen.swift:213 registered with AppModalPresentationCoordinator.dismissPresentedModalBeforePresentingNext, so a hierarchy that still carries these fields is a hierarchy in which the failure came back through the form."
  ],
  "negativeControls": [
    "Wrong username is not evidence of host unreachability, an absolute result:// string typed literally is not evidence of invalid-address or requires-https handling, and a credentials-rejected artifact whose address or username is not the registered valid pair fails criterion 1.",
    "A message shared with any of the other three cases fails criterion 2, as does a generic connection failure line that names no corrective step, or one that repeats a typed credential.",
    "A dismissed or emptied form, a disabled connect control, a sidebar row bearing this attempt's name, or a route that reached the form by any other identifier sequence fails the rubric. Presentation of the form and creation of the row are exclusive: viewModel.addDataSource is reached only on the connected return of FilesScreen.swift:532, and that same connected phase (ConnectionFormPanel.swift:344-345) is the only thing that fires onConnected and dismisses the panel (FilesScreen.swift:208, 484-488), so a still-presented failure form and a created row cannot both exist."
  ]
}
---
# Source Failure Guidance Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
