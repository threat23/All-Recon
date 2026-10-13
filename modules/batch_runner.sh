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

# Source cache manager if available
if [[ -f "$SCRIPT_DIR/cache_manager.sh" ]]; then
    source "$SCRIPT_DIR/cache_manager.sh"
    USE_CACHE=true
else
    USE_CACHE=false
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BATCH_LOG="logs/batch_$TIMESTAMP.log"
BATCH_OUTPUT="output/batch_$TIMESTAMP"

mkdir -p logs output "$BATCH_OUTPUT"

log_batch() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$BATCH_LOG"
}

usage() {
    echo "Usage: $0 <targets_file> [scan_mode] [max_concurrency] [timeout_seconds]"
    echo ""
    echo "Scan Modes:"
    echo "  recon       - DNS, WHOIS, Port & Service Mapping (Default)"
    echo "  whois       - WHOIS, Reverse DNS, Netblocks & Related Domains"
    echo "  subdomain   - Subdomain Discovery & OSINT"
    echo "  passive     - Passive OSINT (crt.sh, Wayback, RDAP)"
    echo "  web         - Web Vulnerability Scanning"
    echo "  asn         - Passive ASN / IP-prefix enrichment"
    echo "  http        - HTTP / TLS fingerprinting"
    echo "  email       - DNS and email security audit (domain targets)"
    echo "  all         - Comprehensive scan including expanded recon modules"
    echo ""
    echo "Parameters:"
    echo "  targets_file    - Path to text file containing target IPs, domains, or URLs"
    echo "  max_concurrency - Number of parallel workers (default: 5)"
    echo "  timeout_seconds - Timeout per scan in seconds (default: 3600 = 1 hour)"
    echo ""
    echo "Examples:"
    echo "  $0 targets.txt recon 5"
    echo "  $0 targets.txt subdomain 3 1800"
    echo "  $0 targets.txt all 10 7200"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGETS_FILE="$1"
SCAN_MODE="${2:-recon}"
MAX_CONCURRENCY="${3:-5}"
SCAN_TIMEOUT="${4:-3600}"  # Default 1 hour timeout per scan

if [[ ! -f "$TARGETS_FILE" ]]; then
    echo "❌ Target file not found: $TARGETS_FILE"
    exit 1
fi

log_batch "🚀 Initializing Batch Runner..."
log_batch "📋 Target File : $TARGETS_FILE"
log_batch "🎯 Scan Mode   : $SCAN_MODE"
log_batch "⚡ Concurrency : $MAX_CONCURRENCY workers"
log_batch "⏱️  Timeout     : $SCAN_TIMEOUT seconds per scan"

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
    echo "❌ No valid targets found in $TARGETS_FILE"
    exit 1
fi

log_batch "✅ Loaded $TOTAL_TARGETS targets from $TARGETS_FILE"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🎯 ALL-RECON MULTI-TARGET BATCH SCANNER"
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

    # Run with timeout
    (
        case "$mode" in
            recon)
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/recon.sh" "$target" all &> "$target_out/recon.log"
                ;;
            whois)
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/whois_recon.sh" "$target" all &> "$target_out/whois.log"
                ;;
            subdomain)
                if type is_valid_domain &>/dev/null && is_valid_domain "$target"; then
                    timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/subdomain_finder.sh" "$target" osint &> "$target_out/subdomains.log"
                else
                    echo "[!] $target is not a valid domain, skipping subdomain scan" > "$target_out/subdomains.log"
                fi
                ;;
            passive)
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/passive.sh" "$target" &> "$target_out/passive.log"
                ;;
            web)
                local url="$target"
                if [[ ! "$target" =~ ^https?:// ]]; then
                    url="http://$target"
                fi
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/web_vulnerabilities.sh" "$url" 10 &> "$target_out/web_vulns.log"
                ;;
            asn)
                timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/asn_recon.py" "$target" --output-dir "$target_out" &> "$target_out/asn.log"
                ;;
            http)
                timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/http_fingerprint.py" "$target" --output-dir "$target_out" &> "$target_out/http.log"
                ;;
            email)
                timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/dns_email_audit.py" "$target" --output-dir "$target_out" &> "$target_out/email.log"
                ;;
            all)
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/recon.sh" "$target" all &> "$target_out/recon.log"
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/whois_recon.sh" "$target" all &> "$target_out/whois.log"
                if type is_valid_domain &>/dev/null && is_valid_domain "$target"; then
                    timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/subdomain_finder.sh" "$target" osint &> "$target_out/subdomains.log"
                fi
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/passive.sh" "$target" &> "$target_out/passive.log"
                local url="$target"
                if [[ ! "$target" =~ ^https?:// ]]; then
                    url="http://$target"
                fi
                timeout "$SCAN_TIMEOUT" bash "$SCRIPT_DIR/web_vulnerabilities.sh" "$url" 10 &> "$target_out/web_vulns.log"
                timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/asn_recon.py" "$target" --output-dir "$target_out" &> "$target_out/asn.log"
                timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/http_fingerprint.py" "$target" --output-dir "$target_out" &> "$target_out/http.log"
                domain_candidate=$(printf '%s' "$target" | sed -E 's|^https?://||; s|/.*$||; s|:[0-9]+$||')
                if type is_valid_domain &>/dev/null && is_valid_domain "$domain_candidate"; then
                    timeout "$SCAN_TIMEOUT" python3 "$SCRIPT_DIR/dns_email_audit.py" "$domain_candidate" --output-dir "$target_out" &> "$target_out/email.log"
                else
                    echo "[!] DNS/email audit requires a domain target; skipped." > "$target_out/email.log"
                fi
                ;;
            *)
                echo "Unknown mode: $mode" > "$target_out/error.log"
                ;;
        esac
    )

    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "[!] [TIMEOUT] Scan timed out for: $target" | tee -a "$BATCH_LOG"
        echo "Scan timed out after $SCAN_TIMEOUT seconds" >> "$target_out/error.log"
        return 124
    elif [[ $exit_code -ne 0 ]]; then
        echo "[!] [ERROR] Scan failed for: $target (exit code: $exit_code)" | tee -a "$BATCH_LOG"
        return $exit_code
    fi

    echo "[+] [COMPLETE] Finished: $target" | tee -a "$BATCH_LOG"
}

export -f run_target_scan log_batch
export SCRIPT_DIR BATCH_OUTPUT BATCH_LOG SCAN_TIMEOUT

# Parallel worker loop with improved job management
current=0
active_jobs=0
completed_jobs=0
failed_jobs=0
declare -a PIDS=()

for target in "${TARGET_LIST[@]}"; do
    ((current++))
    echo -e "▶ [$current/$TOTAL_TARGETS] Dispatching worker for: \e[1;36m$target\e[0m"

    run_target_scan "$target" "$SCAN_MODE" &
    local pid=$!
    PIDS+=($pid)
    ((active_jobs++))

    # Wait for a job to complete if we've reached max concurrency
    if [[ $active_jobs -ge $MAX_CONCURRENCY ]]; then
        for pid in "${PIDS[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid"
                local exit_code=$?
                ((active_jobs--))
                ((completed_jobs++))
                [[ $exit_code -ne 0 ]] && ((failed_jobs++))
                echo -e "✓ Progress: [$completed_jobs/$TOTAL_TARGETS] completed, [$failed_jobs] failed"
                break
            fi
        done
        # If no job finished, wait for one
        if [[ $active_jobs -ge $MAX_CONCURRENCY ]]; then
            wait -n 2>/dev/null || wait
            local exit_code=$?
            ((active_jobs--))
            ((completed_jobs++))
            [[ $exit_code -ne 0 ]] && ((failed_jobs++))
            echo -e "✓ Progress: [$completed_jobs/$TOTAL_TARGETS] completed, [$failed_jobs] failed"
        fi
    fi
done

# Wait for remaining background jobs to finish
for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        wait "$pid"
        local exit_code=$?
        ((completed_jobs++))
        [[ $exit_code -ne 0 ]] && ((failed_jobs++))
    fi
done

log_batch "✅ All $TOTAL_TARGETS batch targets completed execution."
log_batch "📊 Stats: $completed_jobs completed, $failed_jobs failed"

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
            echo "📊 Target: $target_name"
            ls -lh "$target_dir" | tail -n +2 | awk '{print "   -", $9, "(" $5 ")"}'
            echo ""
        fi
    done
    echo "═══════════════════════════════════════════════════════════════"
} | tee "$SUMMARY_FILE"

echo ""
echo "🎉 Batch Scanning Complete!"
echo "📁 Results saved to: $BATCH_OUTPUT/"
echo "📋 Summary report : $SUMMARY_FILE"
echo "📋 Session Log     : $BATCH_LOG"
