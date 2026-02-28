#!/usr/bin/env bash
#
# dmesg_gaps.sh - Find the top N largest time gaps between dmesg lines
#
# Usage: dmesg_gaps.sh [FILE] [N]
#        dmesg_gaps.sh [N]          (reads from stdin)
#        dmesg_gaps.sh              (reads from stdin, N=20)
#
# Examples:
#   dmesg | dmesg_gaps.sh
#   dmesg_gaps.sh dmesg.out 10
#   dmesg_gaps.sh dmesg.out

set -euo pipefail

# Parse arguments: accept [FILE] [N] in either order, file detected by existence
N=20
FILE=""

for arg in "$@"; do
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        N="$arg"
    elif [[ -f "$arg" ]]; then
        FILE="$arg"
    else
        echo "Error: '$arg' is not a valid file or integer" >&2
        exit 1
    fi
done

input() {
    if [[ -n "$FILE" ]]; then
        cat "$FILE"
    else
        cat
    fi
}

# Use awk to extract timestamps, compute gaps, then sort and print top N
input | awk -v N="$N" '
/^\[[ 0-9]+\.[0-9]+\]/ {
    # Extract timestamp: [  1.234567] -> 1.234567
    match($0, /\[[ 0-9]+\.[0-9]+\]/)
    ts_str = substr($0, RSTART+1, RLENGTH-2)
    ts = ts_str + 0   # convert to float

    if (NR > 1 && prev_ts != "") {
        gap = ts - prev_ts
        # Store: gap, previous line, current line
        gaps[count] = gap
        line_a[count] = prev_line
        line_b[count] = $0
        count++
    }

    prev_ts = ts
    prev_line = $0
}

END {
    # Sort indices by gap descending (simple insertion sort for awk portability)
    for (i = 0; i < count; i++) idx[i] = i

    for (i = 1; i < count; i++) {
        key_idx = idx[i]
        key_gap = gaps[key_idx]
        j = i - 1
        while (j >= 0 && gaps[idx[j]] < key_gap) {
            idx[j+1] = idx[j]
            j--
        }
        idx[j+1] = key_idx
    }

    top = (N < count) ? N : count
    for (i = 0; i < top; i++) {
        k = idx[i]
        printf "--- gap: %.6f s ---\n", gaps[k]
        print line_a[k]
        print line_b[k]
        if (i < top - 1) print ""
    }
}
'
