#!/bin/sh

set -eu

here=$(cd "$(dirname "$0")" && pwd)

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

if [ ! -f "$here/tla2tools.jar" ]; then
    echo "fetching tla2tools.jar"
    curl -sL -o "$here/tla2tools.jar" \
        https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
fi

exec "$java_command" -cp "$here/tla2tools.jar" tlc2.TLC \
    -config "$here/ConsoleSession.cfg" -cleanup "$here/ConsoleSession.tla"
