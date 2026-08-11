#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - PASSIVE OSINT WRAPPER
# Wrapper around modules/passive.py for certificate transparency,
# Wayback, RDAP, and (optionally) Shodan passive reconnaissance.
# ═══════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"
LOGS_DIR="$PROJECT_ROOT/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOGS_DIR/passive_$TIMESTAMP.log"
}

usage() {
    echo "Usage: $0 <domain> [sources]"
    echo "  domain   target domain (e.g. example.com)"
    echo "  sources  comma-separated collectors (default: crtsh,wayback,rdap)"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGET="$1"
SOURCES="${2:-crtsh,wayback,rdap}"
OUT_DIR="$OUTPUT_DIR/passive_${TARGET//[^a-zA-Z0-9]/_}_$TIMESTAMP"
CACHE_DIR="$OUT_DIR/.cache"
OUT_FILE="$OUT_DIR/passive_results.json"

mkdir -p "$OUT_DIR" "$CACHE_DIR"

if ! command -v python3 &>/dev/null; then
    echo "[!] python3 is required but not installed."
    exit 1
fi

log "🔍 Starting passive OSINT recon for $TARGET (sources: $SOURCES)"

python3 "$PROJECT_ROOT/modules/passive.py" \
    "$TARGET" \
    --sources "$SOURCES" \
    --output "$OUT_FILE" \
    --cache-dir "$CACHE_DIR" \
    --timeout 30

log "✅ Passive recon complete. Results: $OUT_FILE"
echo ""
echo "📁 Results saved to: $OUT_DIR"
