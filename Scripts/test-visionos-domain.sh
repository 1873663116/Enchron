#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CREDENTIALS_SOURCE="$ROOT/Tests/EmbyServerCredentials.local.json"
CREDENTIALS_RESOURCE="$ROOT/Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
DESTINATION_ID="${1:?usage: Scripts/test-visionos-domain.sh <visionOS Simulator destination id>}"

if [[ ! -f "$CREDENTIALS_SOURCE" ]]; then
  print -u2 "missing $CREDENTIALS_SOURCE"
  exit 1
fi

if [[ -e "$CREDENTIALS_RESOURCE" ]]; then
  print -u2 "refusing to replace $CREDENTIALS_RESOURCE"
  exit 1
fi

trap 'rm -f "$CREDENTIALS_RESOURCE"' EXIT
cp "$CREDENTIALS_SOURCE" "$CREDENTIALS_RESOURCE"

xcodebuild test \
  -project "$ROOT/Enchron.xcodeproj" \
  -scheme EnchronDomainTests \
  -testPlan EnchronDomain \
  -destination "id=$DESTINATION_ID" \
  CODE_SIGNING_ALLOWED=NO
