#!/bin/zsh
# 删除 .scratch/ 下超过保留期的条目。用法: zsh Scripts/scratch-prune.zsh [保留天数，默认 14]
set -euo pipefail

days=${1:-14}
root=$(git rev-parse --show-toplevel)/.scratch

[[ -d $root ]] || exit 0
find "$root" -mindepth 1 -maxdepth 1 -mtime +"$days" -print -exec rm -rf {} +
