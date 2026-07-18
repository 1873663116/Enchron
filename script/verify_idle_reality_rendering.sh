#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "usage: $0 /path/to/EnchronMacOS.app" >&2
    exit 2
fi

app_bundle="$1"
process_name="${app_bundle:t:r}"
temporary_directory=$(/usr/bin/mktemp -d /tmp/ench-idle-reality.XXXXXX)
process_id=""

cleanup() {
    if [[ -n "${process_id:-}" ]] && /bin/kill -0 "$process_id" 2>/dev/null; then
        /bin/kill "$process_id" 2>/dev/null || true
    fi
    /bin/rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

/usr/bin/pkill -x "$process_name" 2>/dev/null || true
/usr/bin/open -n "$app_bundle"

for _ in {1..20}; do
    process_id=$(/usr/bin/pgrep -x "$process_name" | /usr/bin/head -1 || true)
    [[ -n "$process_id" ]] && break
    /bin/sleep 0.25
done

if [[ -z "$process_id" ]]; then
    echo "failed to launch $process_name" >&2
    exit 2
fi

/bin/sleep 3

cpu_samples="$temporary_directory/cpu.txt"
/usr/bin/top -l 9 -s 1 -pid "$process_id" -stats pid,cpu,mem,threads,state,time |
    /usr/bin/awk '/^PID / { getline; sample += 1; if (sample > 1) print $2+0 }' > "$cpu_samples"

cpu_median=$(
    /usr/bin/sort -n "$cpu_samples" |
        /usr/bin/awk '{ value[NR]=$1 } END {
            if (NR == 0) print "n/a"
            else if (NR % 2) print value[(NR + 1) / 2]
            else printf "%.2f", (value[NR / 2] + value[NR / 2 + 1]) / 2
        }'
)
rss_kb=$(/bin/ps -p "$process_id" -o rss= | /usr/bin/tr -d ' ')

sample_file="$temporary_directory/sample.txt"
/usr/bin/sample "$process_id" 2 1 -file "$sample_file" >/dev/null
callback_pattern='ARView\.commonRenderCallback|DisplayLinkClock::initDispatchSource|CoreRE.*DisplayLink'
callback_lines=$(
    (rg -c "$callback_pattern" "$sample_file" 2>/dev/null || true) |
        /usr/bin/awk -F: '{ total += $NF } END { print total + 0 }'
)

echo "process_id=$process_id"
echo "cpu_samples_percent=$(/usr/bin/paste -sd, "$cpu_samples")"
echo "cpu_median_percent=$cpu_median"
echo "rss_kb=$rss_kb"
echo "reality_render_callback_lines=$callback_lines"

if [[ "$callback_lines" -ne 0 ]]; then
    echo "FAIL: idle RealityKit render callbacks are still active" >&2
    exit 1
fi

echo "PASS: no idle RealityKit render callbacks detected"
