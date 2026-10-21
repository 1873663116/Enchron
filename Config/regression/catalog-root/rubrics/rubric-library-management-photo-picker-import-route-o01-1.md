---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.photo-picker-import-route.o01@1",
  "title": "Photo Picker Import Route",
  "criteria": [
    "The product Add from Photos entry opens the system photo picker; Device Hub selects the reviewed video asset and the PhotosPicker transfer returns through the production completion.",
    "The final systemImportObservation is bound to the seeded photo asset UUID and contains exactly one persistent app-managed reference named Enchron-System-Import-30s.mp4 with digest sha256:31444db5d84f3c8ea9af0f22a4d8602bd9bc2848d2e23ff857fbaf4ede9316aa and the app-managed photo-transfer delivery domain."
  ],
  "negativeControls": [
    "Element existence or isHittable alone does not prove that the product received the action.",
    "A route reached only through a diagnostic injection cannot satisfy a user-path delivery criterion.",
    "An injected inbox import, a runtime human permission step, or selection without a persistent reference cannot satisfy the rubric."
  ]
}
---
# Photo Picker Import Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
