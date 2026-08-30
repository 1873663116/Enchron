---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.home-poster-and-next-up.o01@1",
  "title": "Home Poster And Next Up",
  "criteria": [
    "The bound emby.evidence inlines the host emby-aggregate report and the home inspect: home.shelves itemIDs include receipt.catalog.seriesID and episodeID from that report.",
    "The bound document inlines the pre-relaunch inspect whose home.activations holds an activation with surface poster, cardIdentifier Emby-PosterCard-<itemID>, and resultingItemID equal to the inlined host report's receipt.catalog.seriesID. The producer inspect's own home.activations holds an activation with surface nextUp whose itemID is listed by the home.shelves entry of kind nextUp and whose cardIdentifier is Emby-PosterCard- followed by that itemID: the Next Up shelf renders poster cards, so no still card can witness it. An in-memory activation journal cleared by relaunch cannot be the sole witness for the earlier poster activation."
  ],
  "negativeControls": [
    "Element existence or isHittable alone does not prove that the product received the action.",
    "A route reached only through a diagnostic injection cannot satisfy a user-path delivery criterion.",
    "home.shelves missing the live catalog itemIDs, a poster activation present only on an unbound earlier inspect, or activations that lack poster or nextUp cannot Satisfy."
  ]
}
---
# Home Poster And Next Up

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
