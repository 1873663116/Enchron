---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:runtime.no-human-or-wearer",
  "title": "Runtime no human or wearer",
  "statement": "Runtime contains no human, wearer, skipped, voided, or not-applicable state.",
  "valueType": "boolean",
  "value": true,
  "provenance": {
    "kind": "product-constant",
    "path": "Config/regression/catalog-root/semantic-authority.json",
    "pattern": "\"runtimeHumanActorAllowed\":\\s*(true|false)",
    "transform": "boolean-negated"
  }
}
---
# Runtime no human or wearer

The blueprint recorded design-time status `reviewed` and value `true`.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
