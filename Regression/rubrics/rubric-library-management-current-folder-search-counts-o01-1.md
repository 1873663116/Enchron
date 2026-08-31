---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.current-folder-search-counts.o01@1",
  "title": "Current-folder search and counts",
  "criteria": [
    "The two inlined library snapshots establish the scope the tree is read in. relatedResults[0] is call 04's root reading, taken before call 05 opened the folder: its references hold exactly one entry, sdr-bframe-aggregate-30s.mkv with folderID root, and its folders hold Regression Search Folder. relatedResults[1] is call 06's afterSnapshot, taken after that entry: it holds exactly two references, and sdr-bframe-multiaudio-avsync-30s.mp4 carries the folderID of Regression Search Folder while sdr-bframe-aggregate-30s.mkv still carries root, so the second import landed in the current folder and the first did not.",
    "The bound tree is the FileBrowsing-FilesScreen reading call 08 takes inside that folder with the search query standing, and it names its own count and reference. relatedResults[2] is call 07's postActionState, and the query is read from its elementAfterAction -- the second reading of FileBrowsing-FilesScreen-search, taken once replaceText returned -- which holds exactly sdr-bframe. Its matchedElement is the same field as the runner found it before it typed, which is what that name means for every action that is not a snapshot, and it is not what this criterion reads. In the bound response hierarchy FileBrowsing-FilesScreen-itemCount reads exactly 1 items -- the itemCountBar Text at Modules/MediaLibrary/Views/FilesScreen.swift:819-827 whose totalItemCount is displayedLibraryFolders.count plus displayedLibraryReferences.count -- and exactly one grid card is present, MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4. sdr-bframe-aggregate-30s.mkv matches the same typed query and is absent, so what removed it is the current-folder scope and not the predicate."
  ],
  "negativeControls": [
    "A MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv card anywhere in the bound hierarchy, or an itemCount that is not 1 items, violates the current-folder scope: that ancestor reference matches the typed query and must still be excluded.",
    "A count with no matching card, a card with no matching count, a call-07 elementAfterAction that is absent, or that is a FileBrowsing-FilesScreen-search holding anything other than sdr-bframe, or a root-scope reading substituted for the in-folder one cannot satisfy the rubric."
  ]
}
---
# Current-folder search and counts

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
