#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-$HOME/.claude/plugins/marketplaces/omc/skills}"
DST="${2:-$HOME/.codex/skills}"
PREFIX="${3:-omc-}"

if [[ ! -d "$SRC" ]]; then
  echo "Source skills directory not found: $SRC" >&2
  exit 1
fi
mkdir -p "$DST"

installed=0
updated=0
skipped=0

for dir in "$SRC"/*; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  [[ "$name" == "AGENTS.md" ]] && continue
  target="$DST/${PREFIX}${name}"

  if [[ -d "$target" ]]; then
    rsync -a --delete "$dir/" "$target/"
    updated=$((updated+1))
  else
    mkdir -p "$target"
    rsync -a "$dir/" "$target/"
    installed=$((installed+1))
  fi
done

echo "Done. installed=$installed updated=$updated skipped=$skipped"
