#!/bin/bash

set -euo pipefail

ENCHRON_WORKSPACE_DEFAULT="/Volumes/Cortisol/DevSpace/EnchronWorkspace"

toolchain() {
  if [ -d /opt/homebrew/bin ]; then
    export PATH="/opt/homebrew/bin:$PATH"
  fi
  local venv="${ENCHRON_WORKSPACE}/wt-ci-venv"
  if [ -x "$venv/bin/python3" ]; then
    export PATH="$venv/bin:$PATH"
  fi
  if [ -z "${PYTHONPATH:-}" ]; then
    export PYTHONPATH="$(python3 -S -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
  fi
}

prepare_venv() {
  local venv="$1"
  if ! "$venv/bin/python3" -c "" 2>/dev/null; then
    rm -rf "$venv"
    python3 -S -m venv --without-pip "$venv"
  fi
}

prepare_checkout() {
  local workspace="$1"
  local main="$workspace/Enchron"
  local repo="$workspace/wt-ci"
  if [ ! -d "$repo" ]; then
    git -C "$main" worktree add --detach "$repo" HEAD
  fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    local auth
    auth=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64)
    if [ "${ENCHRON_FETCH_TAGS:-0}" = "1" ]; then
      git -C "$repo" -c credential.helper= \
        -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $auth" \
        fetch --no-tags --force origin \
          '+refs/heads/*:refs/remotes/origin/*' \
          '+refs/tags/*:refs/tags/*'
    else
      git -C "$repo" -c credential.helper= \
        -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $auth" \
        fetch --no-tags --force origin '+refs/heads/*:refs/remotes/origin/*'
    fi
  fi
  git -C "$repo" checkout --force --detach "${ENCHRON_REVISION:-refs/remotes/origin/main}"
  git -C "$repo" clean -ffdx \
    -e .build -e .scratch/DerivedData -e .scratch/SourcePackages
  "$repo/Scripts/provision_vendored_ffmpeg.sh" "$main"
  "$repo/Scripts/provision_vendored_bluray.sh" "$main"
  if [ "${ENCHRON_TEST_SERVICES:-0}" = "1" ]; then
    trap 'rm -f "$repo/.env"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    install -m 600 "$main/.env" "$repo/.env"
  fi
}

emit() {
  printf 'export PATH=%q\n' "$PATH"
  printf 'export PYTHONPATH=%q\n' "$PYTHONPATH"
}

main() {
  local mode="${1:-ci}"
  local emit_only=0
  if [ "${2:-}" = "--emit" ]; then
    emit_only=1
  fi
  export ENCHRON_WORKSPACE="${ENCHRON_WORKSPACE:-$ENCHRON_WORKSPACE_DEFAULT}"
  toolchain
  if [ "$emit_only" = "1" ]; then
    emit
    return 0
  fi
  if [ "$mode" = "ci" ]; then
    prepare_venv "$ENCHRON_WORKSPACE/wt-ci-venv"
    toolchain
    prepare_checkout "$ENCHRON_WORKSPACE"
    export ENCHRON_WORKSPACE
    export ENCHRON_MAIN="$ENCHRON_WORKSPACE/Enchron"
    export ENCHRON_REPO="$ENCHRON_WORKSPACE/wt-ci"
  fi
}

main "$@"
