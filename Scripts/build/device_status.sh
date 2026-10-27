set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_UDID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)
      TARGET_UDID="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $0 [--udid <udid>]" >&2
      exit 64
      ;;
  esac
done

JSON_FILE="$(mktemp -t enchron-devices)"
trap 'rm -f "$JSON_FILE"' EXIT

xcrun devicectl list devices --json-output "$JSON_FILE" --timeout "${ENCHRON_DEVICE_TIMEOUT:-30}" >/dev/null

python3 - "$JSON_FILE" "$TARGET_UDID" <<'PY'
import json
import sys

path, target = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    devices = json.load(handle)["result"]["devices"]

rows = []
for device in devices:
    hardware = device.get("hardwareProperties") or {}
    properties = device.get("deviceProperties") or {}
    connection = device.get("connectionProperties") or {}
    udid = hardware.get("udid") or ""
    for hostname in connection.get("potentialHostnames") or []:
        candidate = hostname.split(".", 1)[0]
        if len(candidate) == 36 and candidate.count("-") == 4:
            udid = udid or candidate
    if not udid:
        udid = device.get("identifier", "")
    name = properties.get("name", "")
    platform = hardware.get("platform", "")
    reality = hardware.get("reality", "simulated")
    pairing = connection.get("pairingState", "")
    tunnel = connection.get("tunnelState", "")
    transport = connection.get("transportType", "")
    last = connection.get("lastConnectionDate", "")
    if reality == "physical" and platform == "visionOS" and pairing == "paired":
        verdict = "installable"
    elif reality != "physical":
        verdict = "simulator"
    elif pairing != "paired":
        verdict = "not paired"
    else:
        verdict = "other platform"
    rows.append((name, udid, platform, reality, pairing, tunnel, transport, last, verdict))

physical = [row for row in rows if row[3] == "physical" and row[2] == "visionOS"]
selected = [row for row in physical if row[1] == target] if target else physical

print(f"{'NAME':<34} {'UDID':<40} {'PAIRING':<9} {'TUNNEL':<12} {'TRANSPORT':<12} {'VERDICT':<12} LAST CONNECTION")
for name, udid, _platform, _reality, pairing, tunnel, transport, last, verdict in selected:
    print(f"{name:<34} {udid:<40} {pairing:<9} {tunnel:<12} {transport:<12} {verdict:<12} {last}")

if not selected:
    print("no physical visionOS device found by devicectl", file=sys.stderr)
    raise SystemExit(1)

installable = [row for row in selected if row[8] == "installable"]
if not installable:
    print("physical visionOS devices are present but none is paired for install", file=sys.stderr)
    raise SystemExit(1)

print()
print("install with: xcrun devicectl device install app --device <UDID> <Enchron.app>")
print("tunnel disconnected is not proof of failure; the install attempt decides")
PY
