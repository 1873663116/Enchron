---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:library-management.files-picker-import-route.o01@1",
  "title": "Files Picker Import Route",
  "criteria": [
    "The product Add Files entry opens the system Files picker; the Device Hub Home round trip brings the independent system window forward, then Device Hub selects the reviewed Local Storage fixture and returns through the production fileImporter completion.",
    "The final systemImportObservation is bound to the system-import runtime identity and contains exactly one persistent file-backed reference named Enchron-System-Import-30s.mp4 with digest sha256:31444db5d84f3c8ea9af0f22a4d8602bd9bc2848d2e23ff857fbaf4ede9316aa and the files-provider security-scope delivery domain."
  ],
  "negativeControls": [
    "Element existence or isHittable alone does not prove that the product received the action.",
    "A route reached only through a diagnostic injection cannot satisfy a user-path delivery criterion.",
    "Using importMedia to bypass the picker, a human permission response during runtime, or a card without product-side URL delivery cannot satisfy the rubric."
  ]
}
---
# Files Picker Import Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
