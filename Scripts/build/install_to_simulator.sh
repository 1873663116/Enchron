#!/usr/bin/env bash
set -euo pipefail

# Installs Enchron.app to a visionOS simulator and launches it.
#
# Refuses to install a bundle that carries no code signature. Simulator
# builds are ad-hoc signed; a bundle built with CODE_SIGNING_ALLOWED=NO
# (e.g. test artifacts) has no signature at all, loses its keychain
# identity, and hits OSStatus -34018 on credential access.
#
# usage: install_to_simulator.sh [--check] [SIMULATOR_UDID] [APP_BUNDLE]
#   --check   validate the signature only, do not install or launch.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="install"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
fi

SIM_UDID="${1:?usage: $0 [--check] SIMULATOR_UDID [APP_BUNDLE]}"
APP_BUNDLE="${2:-$ROOT_DIR/.scratch/derived-data/Build/Products/Debug-xrsimulator/Enchron.app}"
BUNDLE_ID="com.xiongzhipeng.Enchron"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "app bundle not found: $APP_BUNDLE" >&2
  exit 2
fi

SIGNATURE="$(/usr/bin/codesign -dv "$APP_BUNDLE" 2>&1 | /usr/bin/grep '^Signature=' || true)"
if [[ -z "$SIGNATURE" ]]; then
  echo "refusing to install: $APP_BUNDLE has no code signature." >&2
  echo "an unsigned build cannot access the keychain (OSStatus -34018) and" >&2
  echo "will drop stored credentials. Rebuild without CODE_SIGNING_ALLOWED=NO." >&2
  exit 1
fi
echo "signature ok: $SIGNATURE"

if [[ "$MODE" == "check" ]]; then
  exit 0
fi

/usr/bin/xcrun simctl install "$SIM_UDID" "$APP_BUNDLE"
/usr/bin/xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
