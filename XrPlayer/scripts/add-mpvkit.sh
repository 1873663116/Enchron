#!/usr/bin/env bash
set -euo pipefail

# Adds/validates MPVKit Swift Package integration instructions for XrPlayer.
# This script is intentionally non-destructive: it does not edit project.pbxproj.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/../XrPlayer.xcodeproj"
PACKAGE_URL="https://github.com/mpvkit/MPVKit.git"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "error: expected Xcode project at: $PROJECT_PATH" >&2
  exit 1
fi

cat <<TXT
MPVKit integration steps (Xcode GUI, recommended):
1. Open: $PROJECT_PATH
2. Select project 'XrPlayer' in navigator.
3. Open Package Dependencies tab.
4. Click '+' and add package URL:
   $PACKAGE_URL
5. Dependency Rule: Up to Next Major Version (or exact version per release policy).
6. Add product 'MPVKit' to target 'XrPlayer'.
   Note: Swift sources should import module 'Libmpv' for C API symbols.
7. Build once to let Xcode resolve packages.

Optional CLI resolve step after GUI add:
  xcodebuild -project "$PROJECT_PATH" -resolvePackageDependencies
TXT

if command -v rg >/dev/null 2>&1; then
  if rg -q "$PACKAGE_URL" "$PROJECT_PATH/project.pbxproj"; then
    echo
    echo "Status: MPVKit package reference already exists in project.pbxproj"
  else
    echo
    echo "Status: MPVKit package reference not found yet in project.pbxproj"
  fi
fi
