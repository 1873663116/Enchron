---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.series-season-episode-navigation.o01@1",
  "title": "Series Season Episode Navigation",
  "criteria": [
    "In the Emby-Evidence reading inlined from the call taken on the series detail before the season change, the observed detail has itemKind series, its itemID equals the inlined host report's receipt.catalog.seriesID, its declaredSeasonIDs hold at least two identifiers and contain that report's receipt.catalog.seasonID, and its selectedSeasonID is one of those declaredSeasonIDs with a non-empty episodeIDs. The reading has to be the inlined one: the producer's own detail is the episode opened by the last tap, and an episode detail declares no seasons.",
    "The bound emby.evidence carries a seasonTransitions entry for that same series whose requestedSeasonID is a declaredSeasonID other than its beforeSelectedSeasonID, whose afterSelectedSeasonID equals that requestedSeasonID, and whose afterEpisodeIDs are non-empty and share no identifier with its beforeEpisodeIDs, which is the episode list being replaced rather than appended to. In the inlined Emby-Evidence responses taken before and after that season change, the observed detail has itemKind series and publishes an empty playbackActionIDs, because the detail screen renders play actions only for a playable item and a series is not one; the series-level play action the criterion forbids would appear there."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "A poster-only cached view, stale episodes after season change, or navigation through the Emby tab icon mistaken for playback violates the rubric. So does a detail observed with itemKind series that publishes any playbackActionIDs entry, and so does an absent seasonTransitions entry, which is what a season row that vanished before its tap arrived leaves behind. A series detail whose itemID does not equal the inlined receipt's seriesID is mixed-provenance evidence and violates the rubric; a missing inlined pre-change reading produces Indeterminate rather than Satisfied."
  ]
}
---
# Series Season Episode Navigation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
