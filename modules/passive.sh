#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"
mkdir -p "$OUTPUT_DIR"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target> [output_file]"
    exit 1
fi

TARGET="$1"
TARGET_SAFE=$(echo "$TARGET" | sed 's/[^a-zA-Z0-9.-]/_/g')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_FILE="${2:-$OUTPUT_DIR/passive_${TARGET_SAFE}_${TIMESTAMP}.json}"

python3 "$SCRIPT_DIR/passive.py" "$TARGET" "$OUT_FILE"
STATUS=$?
if [[ $STATUS -eq 0 ]]; then
    echo "$OUT_FILE"
fi
exit $STATUS
