#!/bin/sh

set -eu

here=$(cd "$(dirname "$0")" && pwd)
jar="$here/../../console/formal/tla2tools.jar"

java_command=
for candidate in /opt/homebrew/opt/openjdk/bin/java "$(command -v java 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && "$candidate" -version >/dev/null 2>&1; then
        java_command=$candidate
        break
    fi
done
if [ -z "$java_command" ]; then
    echo "no Java runtime; install one with: brew install openjdk" >&2
    exit 2
fi

if [ ! -f "$jar" ]; then
    echo "fetching tla2tools.jar"
    curl -sL -o "$jar" \
        https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
fi

python3 "$here/check_sync.py"

status=0
meta=$(mktemp -d)
trap 'rm -rf "$meta"' EXIT
echo "== design: a lane trims its queue at attach =="
if "$java_command" -cp "$jar" tlc2.TLC -metadir "$meta/design" -config "$here/PlaybackLanes.cfg" "$here/PlaybackLanes.tla" 2>&1 | tee "$here/states/design.log" |
        grep -q "No error has been found"; then
    echo "design: all invariants hold"
else
    echo "design: an invariant failed" >&2
    status=1
fi

echo "== current code: attach trims units that end before the attach position =="
if "$java_command" -cp "$jar" tlc2.TLC -metadir "$meta/current" -config "$here/PlaybackLanesCurrent.cfg" "$here/PlaybackLanes.tla" 2>&1 | tee "$here/states/current.log" |
        grep -q "No error has been found"; then
    echo "current code: no stale delivery found (the defect is fixed)" >&2
    status=1
else
    echo "current code: stale delivery reproduced, as the code stands"
fi

exit $status
