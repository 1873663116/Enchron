#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRATCH="$ROOT_DIR/.scratch"
KEEP_DAYS=2
DELETE=false
PAYLOADS=(
  Build
  CompilationCache.noindex
  Index.noindex
  Logs
  SDKExplicitPrecompiledModules
  SDKStatCaches.noindex
  SourcePackages
)
PROTECTED=(build console derived-data-device loop-fixtures)

usage() {
  cat <<'USAGE'
usage: Scripts/build/prune_build_caches.sh [--delete] [--days N]

Removes DerivedData payloads (Build, CompilationCache.noindex, Index.noindex,
Logs, SDKExplicitPrecompiledModules, SDKStatCaches.noindex, SourcePackages)
from .scratch workspaces and from DerivedData roots nested inside them, except
the fixed caches. Workspaces referenced by tracked or untracked files, and
workspaces modified within N days (default 2), are skipped.

Without --delete the script only reports what it would remove.
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --delete)
      DELETE=true
      shift
      ;;
    --days)
      KEEP_DAYS="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

if ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]]; then
  echo "--days expects a non-negative integer" >&2
  exit 64
fi

if [[ ! -d "$SCRATCH" ]]; then
  echo "no .scratch directory at $SCRATCH"
  exit 0
fi

REFERENCED="$({
  git -C "$ROOT_DIR" grep -h -o '\.scratch/[A-Za-z0-9._-]*' -- '*.md' '*.json' '*.sh' '*.py' '*.swift' '*.txt' 2>/dev/null || true
  while IFS= read -r untracked; do
    grep -h -o '\.scratch/[A-Za-z0-9._-]*' -- "$ROOT_DIR/$untracked" 2>/dev/null || true
  done < <(git -C "$ROOT_DIR" ls-files --others --exclude-standard -- '*.md' '*.json' '*.sh' '*.py' '*.swift' '*.txt' 2>/dev/null || true)
} | sed 's|^\.scratch/||' | sort -u)"

is_protected() {
  local name="$1"
  local protected
  for protected in "${PROTECTED[@]}"; do
    if [[ "$name" == "$protected" ]]; then
      return 0
    fi
  done
  return 1
}

is_referenced() {
  local name="$1"
  if [[ -z "$REFERENCED" ]]; then
    return 1
  fi
  grep -qxF -- "$name" <<<"$REFERENCED"
}

payload_paths() {
  local workspace="$1"
  local payload
  local candidate
  for payload in "${PAYLOADS[@]}"; do
    for candidate in "$workspace/$payload" "$workspace/DerivedData/$payload"; do
      if [[ -e "$candidate" ]]; then
        printf '%s\n' "$candidate"
      fi
    done
  done
}

scan_workspace() {
  local workspace="$1"
  local products
  local root
  local found=()
  local recent
  local payload_path
  while IFS= read -r payload_path; do
    found+=("$payload_path")
  done < <(payload_paths "$workspace")
  while IFS= read -r products; do
    root="$(dirname "$(dirname "$products")")"
    if [[ "$root" == "$SCRATCH/"* && "$root" != "$workspace" ]]; then
      nested_roots+=("$root")
      local nested
      while IFS= read -r nested; do
        found+=("$nested")
      done < <(payload_paths "$root")
    fi
  done < <(find "$workspace" -maxdepth 4 -type d -path "*/Build/Products" 2>/dev/null | sort)
  if [[ "${#found[@]}" -eq 0 ]]; then
    return 2
  fi
  recent="$(find "${found[@]}" -maxdepth 0 -mtime -"$KEEP_DAYS" -print -quit 2>/dev/null || true)"
  if [[ -n "$recent" ]]; then
    return 1
  fi
  targets+=("${found[@]}")
  return 0
}

targets=()
skipped=()
nested_roots=()

while IFS= read -r workspace; do
  name="$(basename "$workspace")"
  if is_protected "$name"; then
    skipped+=("$name: fixed cache")
    continue
  fi
  if is_referenced "$name"; then
    skipped+=("$name: referenced by tracked or untracked files")
    continue
  fi
  set +e
  scan_workspace "$workspace"
  status=$?
  set -e
  case "$status" in
    1) skipped+=("$name: modified within ${KEEP_DAYS}d") ;;
    2) skipped+=("$name: no build cache") ;;
    *) ;;
  esac
done < <(find "$SCRATCH" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "no redundant build caches found"
  exit 0
fi

verified=()
for target in "${targets[@]}"; do
  if [[ "$target" != "$SCRATCH/"* ]]; then
    echo "refuse path outside .scratch: $target" >&2
    exit 1
  fi
  if [[ -L "$target" ]]; then
    echo "refuse symlink: $target" >&2
    exit 1
  fi
  if [[ -e "$target" ]]; then
    verified+=("$target")
  fi
done

if [[ "${#verified[@]}" -eq 0 ]]; then
  echo "no redundant build caches found"
  exit 0
fi

size_kb="$(du -cx "${verified[@]}" 2>/dev/null | tail -1 | cut -f1 || echo 0)"

if [[ "$DELETE" == true ]]; then
  echo "removing ${#verified[@]} payload directories from .scratch"
else
  echo "would remove ${#verified[@]} payload directories from .scratch"
fi
echo "reclaimable: $((size_kb / 1024)) MiB"

for target in "${verified[@]}"; do
  printf '  %s\n' "${target#"$ROOT_DIR"/}"
done

if [[ "${#skipped[@]}" -gt 0 ]]; then
  echo "skipped:"
  printf '  %s\n' "${skipped[@]}"
fi

if [[ "$DELETE" == false ]]; then
  echo "dry run; pass --delete to remove"
  exit 0
fi

for target in "${verified[@]}"; do
  rm -rf -- "$target"
done

for root in "${nested_roots[@]}"; do
  if [[ -d "$root" ]] && [[ -z "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit || true)" ]]; then
    rmdir -- "$root" 2>/dev/null || true
  fi
done

while IFS= read -r workspace; do
  name="$(basename "$workspace")"
  if is_protected "$name"; then
    continue
  fi
  if is_referenced "$name"; then
    continue
  fi
  if [[ -z "$(find "$workspace" -mindepth 1 -maxdepth 1 -print -quit || true)" ]]; then
    rmdir -- "$workspace" 2>/dev/null || true
  fi
done < <(find "$SCRATCH" -mindepth 1 -maxdepth 1 -type d | sort)

echo "removed ${#verified[@]} payload directories, reclaimed $((size_kb / 1024)) MiB"
