#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - MULTI-TARGET BATCH SCANNER MODULE
# Process multiple targets concurrently from a target file
# Philosophy: Scalable automation for target lists & enterprise scope
# ═══════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source validation module if available
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BATCH_LOG="logs/batch_$TIMESTAMP.log"
BATCH_OUTPUT="output/batch_$TIMESTAMP"

mkdir -p logs output "$BATCH_OUTPUT"

log_batch() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$BATCH_LOG"
}

usage() {
    echo "Usage: $0 <targets_file> [scan_mode] [max_concurrency]"
    echo ""
    echo "Scan Modes:"
    echo "  recon       - DNS, WHOIS, Port & Service Mapping (Default)"
    echo "  whois       - WHOIS, Reverse DNS, Netblocks & Related Domains"
    echo "  subdomain   - Subdomain Discovery & OSINT"
    echo "  passive     - Passive OSINT (crt.sh, Wayback, RDAP)"
    echo "  web         - Web Vulnerability Scanning"
    echo "  all         - Comprehensive scan (recon + subdomain + passive + web + whois)"
    echo ""
    echo "Parameters:"
    echo "  targets_file    - Path to text file containing target IPs, domains, or URLs"
    echo "  max_concurrency - Number of parallel workers (default: 5)"
    echo ""
    echo "Examples:"
    echo "  $0 targets.txt recon 5"
    echo "  $0 targets.txt subdomain 3"
    echo "  $0 targets.txt all"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGETS_FILE="$1"
SCAN_MODE="${2:-recon}"
MAX_CONCURRENCY="${3:-5}"

if [[ ! -f "$TARGETS_FILE" ]]; then
    echo "[ERROR] Target file not found: $TARGETS_FILE"
    exit 1
fi

log_batch "-> Initializing Batch Runner..."
log_batch "[LIST] Target File : $TARGETS_FILE"
log_batch "[TARGET] Scan Mode   : $SCAN_MODE"
log_batch "[FAST] Concurrency : $MAX_CONCURRENCY workers"

# Parse valid targets into array
declare -a TARGET_LIST=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip comments and whitespace
    clean_line=$(echo "$line" | sed 's/#.*//' | xargs)
    [[ -z "$clean_line" ]] && continue
    TARGET_LIST+=("$clean_line")
done < "$TARGETS_FILE"

TOTAL_TARGETS=${#TARGET_LIST[@]}

if [[ $TOTAL_TARGETS -eq 0 ]]; then
    echo "[ERROR] No valid targets found in $TARGETS_FILE"
    exit 1
fi

log_batch "[OK] Loaded $TOTAL_TARGETS targets from $TARGETS_FILE"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "[TARGET] ALL-RECON MULTI-TARGET BATCH SCANNER"
echo "════════════════════════════════════════════════════════════════"
echo "Loaded Targets: $TOTAL_TARGETS"
echo "Scan Mode     : $SCAN_MODE"
echo "Concurrency   : $MAX_CONCURRENCY"
echo "Output Dir    : $BATCH_OUTPUT"
echo "════════════════════════════════════════════════════════════════"
echo ""

run_target_scan() {
    local target="$1"
    local mode="$2"
    local target_safe
    target_safe=$(echo "$target" | sed 's/[^a-zA-Z0-9.-]/_/g')
    local target_out="$BATCH_OUTPUT/$target_safe"
    mkdir -p "$target_out"

    echo "[*] [START] Processing: $target" | tee -a "$BATCH_LOG"

    case "$mode" in
        recon)
            bash "$SCRIPT_DIR/recon.sh" "$target" all &> "$target_out/recon.log"
            ;;
        whois)
            bash "$SCRIPT_DIR/whois_recon.sh" "$target" all &> "$target_out/whois.log"
            ;;
        subdomain)
            if type is_valid_domain &>/dev/null && is_valid_domain "$target"; then
                bash "$SCRIPT_DIR/subdomain_finder.sh" "$target" osint &> "$target_out/subdomains.log"
            else
                echo "[!] $target is not a valid domain, skipping subdomain scan" > "$target_out/subdomains.log"
            fi
            ;;
        passive)
            bash "$SCRIPT_DIR/passive.sh" "$target" &> "$target_out/passive.log"
            ;;
        web)
            local url="$target"
            if [[ ! "$target" =~ ^https?:// ]]; then
                url="http://$target"
            fi
            bash "$SCRIPT_DIR/web_vulnerabilities.sh" "$url" 10 &> "$target_out/web_vulns.log"
            ;;
        all)
            bash "$SCRIPT_DIR/recon.sh" "$target" all &> "$target_out/recon.log"
            bash "$SCRIPT_DIR/whois_recon.sh" "$target" all &> "$target_out/whois.log"
            if type is_valid_domain &>/dev/null && is_valid_domain "$target"; then
                bash "$SCRIPT_DIR/subdomain_finder.sh" "$target" osint &> "$target_out/subdomains.log"
            fi
            bash "$SCRIPT_DIR/passive.sh" "$target" &> "$target_out/passive.log"
            local url="$target"
            if [[ ! "$target" =~ ^https?:// ]]; then
                url="http://$target"
            fi
            bash "$SCRIPT_DIR/web_vulnerabilities.sh" "$url" 10 &> "$target_out/web_vulns.log"
            ;;
        *)
            echo "Unknown mode: $mode" > "$target_out/error.log"
            ;;
    esac

    echo "[+] [COMPLETE] Finished: $target" | tee -a "$BATCH_LOG"
}

export -f run_target_scan log_batch
export SCRIPT_DIR BATCH_OUTPUT BATCH_LOG

# Parallel worker loop
current=0
active_jobs=0

for target in "${TARGET_LIST[@]}"; do
    ((current++))
    echo -e "▶ [$current/$TOTAL_TARGETS] Dispatching worker for: \e[1;36m$target\e[0m"

    run_target_scan "$target" "$SCAN_MODE" &
    ((active_jobs++))

    if [[ $active_jobs -ge $MAX_CONCURRENCY ]]; then
        wait -n 2>/dev/null || wait
        ((active_jobs--))
    fi
done

# Wait for all background jobs to finish
wait

log_batch "[OK] All $TOTAL_TARGETS batch targets completed execution."

# Generate consolidated batch summary report
SUMMARY_FILE="$BATCH_OUTPUT/batch_summary.txt"
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "ALL-RECON - BATCH SCAN SUMMARY REPORT"
    echo "Generated: $(date)"
    echo "Scan Mode: $SCAN_MODE"
    echo "Targets Scanned: $TOTAL_TARGETS"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "TARGET RESULTS DIRECTORY BREAKDOWN:"
    echo "───────────────────────────────────────────────────────────────"
    for target_dir in "$BATCH_OUTPUT"/*/; do
        if [[ -d "$target_dir" ]]; then
            target_name=$(basename "$target_dir")
            echo "[REPORT] Target: $target_name"
            ls -lh "$target_dir" | tail -n +2 | awk '{print "   -", $9, "(" $5 ")"}'
            echo ""
        fi
    done
    echo "═══════════════════════════════════════════════════════════════"
} | tee "$SUMMARY_FILE"

echo ""
echo "[PASS] Batch Scanning Complete!"
echo "[DIR] Results saved to: $BATCH_OUTPUT/"
echo "[LIST] Summary report : $SUMMARY_FILE"
echo "[LIST] Session Log     : $BATCH_LOG"
