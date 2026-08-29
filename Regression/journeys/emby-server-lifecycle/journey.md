---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:emby-server-lifecycle",
  "title": "Emby 浏览、播放与服务器观看状态",
  "scenarioRefs": [
    "scenario:emby-server-lifecycle:home-poster-and-next-up",
    "scenario:emby-server-lifecycle:series-season-episode-navigation",
    "scenario:emby-server-lifecycle:episode-resume-and-start-actions",
    "scenario:emby-server-lifecycle:progress-authority-server",
    "scenario:emby-server-lifecycle:artwork-by-image-tag",
    "scenario:emby-server-lifecycle:emby-resume-entry-semantics",
    "scenario:emby-server-lifecycle:emby-artwork-bypasses-loopback"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "emby-test-library-ready",
      "schema": "remote-source.emby-library@2"
    }
  ]
}
---
# Emby 浏览、播放与服务器观看状态

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
