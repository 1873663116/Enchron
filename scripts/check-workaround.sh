#!/bin/bash
# Enchron WORKAROUND 注释检查脚本
# 用法: scripts/check-workaround.sh [目录或文件列表]
# 返回: 0 = 通过, 1 = 存在未标注移除条件的 WORKAROUND
#
# SwiftLint 的单行正则无法可靠检测多行注释模式，
# 因此将 WORKAROUND 检查独立为脚本实现。

set -euo pipefail

TARGET="${1:-XrPlayer}"
FAILED=0

# 查找所有包含 WORKAROUND 的 Swift 文件
while IFS= read -r file; do
    # 对每个文件，检查 WORKAROUND 后的 5 行内是否包含"移除条件"
    line_nums=$(grep -n "WORKAROUND:" "$file" | cut -d: -f1)
    for line_num in $line_nums; do
        end_line=$((line_num + 5))
        context=$(sed -n "${line_num},${end_line}p" "$file")
        if ! echo "$context" | grep -q "移除条件"; then
            echo "❌ $file:$line_num — WORKAROUND 缺少「移除条件」说明"
            echo "   $(sed -n "${line_num}p" "$file")"
            echo ""
            FAILED=1
        fi
    done
done < <(grep -rl "WORKAROUND:" "$TARGET" --include="*.swift" 2>/dev/null || true)

if [ "$FAILED" -eq 0 ]; then
    echo "✅ 所有 WORKAROUND 注释均包含移除条件说明"
fi

exit $FAILED
