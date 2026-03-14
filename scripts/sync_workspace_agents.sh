#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/sync_workspace_agents.py"

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
  echo "sync script not found: $PYTHON_SCRIPT" >&2
  exit 2
fi

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
OBSIDIAN_BASE_DEFAULT="/Users/xiongzhipeng/Library/Mobile Documents/iCloud~md~obsidian/Documents/my_obsidian_vault/项目"
OBSIDIAN_BASE="${OBSIDIAN_PROJECTS_BASE:-$OBSIDIAN_BASE_DEFAULT}"
RESOLVER="${SYNC_RESOLVER:-gemini}"
MODEL="${SYNC_MODEL:-gemini-3-flash}"
OUTPUT_FORMAT="${SYNC_OUTPUT_FORMAT:-text}"

ARGS=(
  "--project-root" "$PROJECT_ROOT"
  "--project-name" "$PROJECT_NAME"
  "--remote-base" "$OBSIDIAN_BASE"
  "--resolver" "$RESOLVER"
  "--resolver-model" "$MODEL"
  "--output-format" "$OUTPUT_FORMAT"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- extra-python-args]

Wrapper around sync_workspace_agents.py with project-root discovery.

Options:
  --apply                 Execute the sync plan.
  --dry-run               Force dry-run mode.
  --json                  Emit machine-readable JSON.
  --text                  Emit human-readable text.
  --resolver NAME         Override resolver: none|gemini|codex.
  --model NAME            Override resolver model.
  --project-name NAME     Override project name used under Obsidian 项目.
  --remote-base PATH      Override Obsidian 项目 base path.
  -h, --help              Show this help.

Environment overrides:
  SYNC_RESOLVER
  SYNC_MODEL
  SYNC_OUTPUT_FORMAT
  OBSIDIAN_PROJECTS_BASE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      ARGS+=("--apply")
      shift
      ;;
    --dry-run)
      shift
      ;;
    --json)
      ARGS+=("--output-format" "json")
      shift
      ;;
    --text)
      ARGS+=("--output-format" "text")
      shift
      ;;
    --resolver)
      ARGS+=("--resolver" "$2")
      shift 2
      ;;
    --model)
      ARGS+=("--resolver-model" "$2")
      shift 2
      ;;
    --project-name)
      ARGS+=("--project-name" "$2")
      shift 2
      ;;
    --remote-base)
      ARGS+=("--remote-base" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      ARGS+=("$@")
      break
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

exec python3 "$PYTHON_SCRIPT" "${ARGS[@]}"
