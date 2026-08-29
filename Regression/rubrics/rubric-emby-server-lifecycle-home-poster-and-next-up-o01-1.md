---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.home-poster-and-next-up.o01@1",
  "title": "Home Poster And Next Up",
  "criteria": [
    "A live server query and product hierarchy agree on the visible poster and Next Up item identities.",
    "A poster opens its media detail route and a Next Up still opens its episode route after any identifier-scoped scroll."
  ],
  "negativeControls": [
    "Element existence or isHittable alone does not prove that the product received the action.",
    "A route reached only through a diagnostic injection cannot satisfy a user-path delivery criterion.",
    "Cached artwork without a live item response, an unscoped swipe, or a non-hittable offscreen card cannot satisfy the rubric."
  ]
}
---
# Home Poster And Next Up

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
