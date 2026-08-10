#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - WHOIS & REVERSE LOOKUP MODULE
# Discover net ranges, co-hosted domains, and IP ranges for a target
# Philosophy: Map the full perimeter around a target
# ═══════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

WR_LOG="logs/whois_reverse_$(date +%Y%m%d_%H%M%S).log"
WR_OUTPUT="output/whois_reverse_$(date +%Y%m%d_%H%M%S)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p logs "$WR_OUTPUT"

log_wr() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$WR_LOG"
}

# Resolve a domain to an IPv4 address (first A record)
resolve_ipv4() {
    local target="$1"
    if type is_valid_ip &>/dev/null && is_valid_ip "$target"; then
        echo "$target"
    else
        dig +short "$target" A 2>/dev/null | head -1
    fi
}

# WHOIS lookup with parsed net-range extraction
whois_lookup() {
    local target="$1"
    log_wr "🔍 Running WHOIS lookup for $target..."

    local output_file="$WR_OUTPUT/whois_$TIMESTAMP.txt"
    local parsed_file="$WR_OUTPUT/whois_parsed_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS LOOKUP: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if ! command -v whois &>/dev/null; then
            echo "❌ whois command not installed. Install with: sudo apt install whois"
            log_wr "❌ whois command not installed"
            exit 1
        fi

        echo "🔎 Raw WHOIS output:"
        echo "────────────────────────────────────────────────────────────────"
        whois "$target" 2>/dev/null || echo "WHOIS query failed or no data"

    } | tee "$output_file"

    # Parse key fields useful for finding other domains / ranges
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS PARSED SUMMARY: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        local raw
        raw=$(whois "$target" 2>/dev/null)

        echo "[Network Ranges / CIDR]"
        echo "$raw" | grep -iE '^(NetRange|inetnum|CIDR|NetBlock|Route|route|IP Network|network:|NetName|netname)[:\s]' | sed 's/^/  /' || echo "  (none found)"

        echo ""
        echo "[Organization / Owner]"
        echo "$raw" | grep -iE '^(OrgName|Organization|org-name|org|netname|descr|description|owner|OwnerName)[:\s]' | sed 's/^/  /' | head -20 || echo "  (none found)"

        echo ""
        echo "[Name Servers]"
        echo "$raw" | grep -iE '^(Name Server|nserver|nameserver|NameServer)[:\s]' | sed 's/^/  /' | sort -u || echo "  (none found)"

        echo ""
        echo "[Registrar / Registrar WHOIS]"
        echo "$raw" | grep -iE '^(Registrar|registrar|Registrar WHOIS Server|ReferralServer|referral)[:\s]' | sed 's/^/  /' | head -10 || echo "  (none found)"

        echo ""
        echo "[Abuse / Contact Emails]"
        echo "$raw" | grep -iE 'Email|abuse|security| noc@|admin@|tech@' | grep -iE '@' | sed 's/^/  /' | sort -u | head -20 || echo "  (none found)"

        echo ""
        echo "[CIDR Blocks Extracted]"
        echo "$raw" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | sort -u | sed 's/^/  /' || echo "  (none found)"

    } | tee "$parsed_file"

    log_wr "✅ WHOIS lookup complete (raw: $output_file, parsed: $parsed_file)"
}

# Reverse DNS (PTR) lookup for an IP
reverse_dns_lookup() {
    local target="$1"
    local ip
    ip=$(resolve_ipv4 "$target")

    log_wr "🔍 Running reverse DNS lookup on $ip..."

    local output_file="$WR_OUTPUT/reverse_dns_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "REVERSE DNS LOOKUP: $target ($ip)"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if [[ -z "$ip" ]]; then
            echo "❌ Could not resolve $target to an IPv4 address"
            log_wr "❌ Could not resolve $target to an IPv4 address"
            exit 1
        fi

        echo "🔎 PTR records (dig -x):"
        echo "────────────────────────────────────────────────────────────────"
        dig -x "$ip" +short 2>/dev/null || echo "  (no PTR records)"

        echo ""
        echo "🔎 Host lookup:"
        echo "────────────────────────────────────────────────────────────────"
        host "$ip" 2>/dev/null || echo "  (host command failed)"

    } | tee "$output_file"

    log_wr "✅ Reverse DNS lookup complete ($output_file)"
}

# Reverse IP lookup using HackerTarget to discover co-hosted domains
reverse_ip_co_hosts() {
    local target="$1"
    local ip
    ip=$(resolve_ipv4 "$target")

    log_wr "🔍 Running reverse IP lookup (co-hosted domains) for $target ($ip)..."

    local output_file="$WR_OUTPUT/reverse_ip_co_hosts_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "REVERSE IP LOOKUP - CO-HOSTED DOMAINS: $target ($ip)"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if [[ -z "$ip" ]]; then
            echo "❌ Could not resolve $target to an IPv4 address"
            log_wr "❌ Could not resolve $target to an IPv4 address"
            exit 1
        fi

        echo "🔎 Querying HackerTarget reverse IP API for $ip..."
        echo "────────────────────────────────────────────────────────────────"
        local resp
        resp=$(curl -s --max-time 25 "https://api.hackertarget.com/reverseiplookup/?q=$ip" 2>/dev/null)

        if [[ -n "$resp" && ! "$resp" =~ (error|API count exceeded|No records) ]]; then
            echo "$resp" | grep -v '^$' | sort -u | sed 's/^/  /'
            local count
            count=$(echo "$resp" | grep -v '^$' | sort -u | wc -l)
            echo ""
            echo "Summary: Found $count co-hosted domain(s) on $ip"
        else
            echo "No co-hosted domains found or API rate limited"
        fi

        echo ""
        echo "🔎 Local reverse DNS for same IP:"
        echo "────────────────────────────────────────────────────────────────"
        dig -x "$ip" +short 2>/dev/null | sed 's/^/  /' || echo "  (no PTR records)"

    } | tee "$output_file"

    log_wr "✅ Reverse IP lookup complete ($output_file)"
}

# Extract network ranges from WHOIS and enumerate reverse DNS for a sample
netrange_discovery() {
    local target="$1"
    log_wr "🔍 Discovering network ranges for $target..."

    local output_file="$WR_OUTPUT/netrange_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "NETWORK RANGE DISCOVERY: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if ! command -v whois &>/dev/null; then
            echo "❌ whois command not installed. Install with: sudo apt install whois"
            exit 1
        fi

        local raw
        raw=$(whois "$target" 2>/dev/null)

        echo "🔎 CIDR / NetRange blocks from WHOIS:"
        echo "────────────────────────────────────────────────────────────────"
        echo "$raw" | grep -iE '^(NetRange|inetnum|CIDR|NetBlock|Route|route)[:\s]' | sed 's/^/  /' || echo "  (none found)"

        echo ""
        echo "🔎 Extracted CIDR notation blocks:"
        echo "────────────────────────────────────────────────────────────────"
        local cidr_list
        cidr_list=$(echo "$raw" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | sort -u)
        if [[ -n "$cidr_list" ]]; then
            echo "$cidr_list" | sed 's/^/  /'
            echo ""
            echo "Summary: $(echo "$cidr_list" | wc -l) CIDR block(s) identified"
        else
            echo "  (no CIDR blocks found)"
        fi

        echo ""
        echo "🔎 Network boundary hints:"
        echo "────────────────────────────────────────────────────────────────"
        echo "$raw" | grep -iE '^(inetnum|NetRange)[:\s]' | sed 's/^/  /' || echo "  (none found)"

    } | tee "$output_file"

    log_wr "✅ Network range discovery complete ($output_file)"
}

# Run all WHOIS and reverse lookup checks
run_all() {
    local target="$1"
    log_wr "🔍 Starting comprehensive WHOIS & reverse lookup on $target..."

    whois_lookup "$target"
    echo ""

    # Resolve IP once for reverse operations
    local ip
    ip=$(resolve_ipv4 "$target")
    if [[ -n "$ip" ]]; then
        reverse_dns_lookup "$target"
        echo ""
        reverse_ip_co_hosts "$target"
        echo ""
    else
        log_wr "⚠️ Could not resolve $target to an IPv4 address; skipping reverse lookups"
    fi

    netrange_discovery "$target"
    echo ""

    # Generate consolidated summary
    local summary_file="$WR_OUTPUT/summary_$TIMESTAMP.txt"
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS & REVERSE LOOKUP SUMMARY"
        echo "Target: $target"
        echo "Date: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Files generated:"
        ls -1 "$WR_OUTPUT"/ | sed 's/^/  /'
        echo ""
        echo "CIDR blocks found:"
        grep -h -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' "$WR_OUTPUT"/whois_parsed_*.txt "$WR_OUTPUT"/netrange_*.txt 2>/dev/null | sort -u | sed 's/^/  /' || echo "  (none)"
        echo ""
        echo "Co-hosted domains found (if any):"
        grep -v '════════════════\|REVERSE IP\|Querying\|Summary\|Co-hosted\|Local\|PTR\|^[[:space:]]*$' "$WR_OUTPUT"/reverse_ip_co_hosts_*.txt 2>/dev/null | sort -u | sed 's/^[[:space:]]*/  /' | head -30 || echo "  (none)"
    } | tee "$summary_file"

    log_wr "✅ Comprehensive WHOIS & reverse lookup complete (summary: $summary_file)"
}

# Main usage
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target> [mode]"
    echo ""
    echo "Modes:"
    echo "  whois     - WHOIS lookup with parsed net ranges & contacts"
    echo "  reverse   - Reverse DNS + reverse IP co-hosted domain lookup"
    echo "  netrange  - Network range / CIDR extraction from WHOIS"
    echo "  all       - Run all checks (default)"
    echo ""
    echo "Target: domain name or IPv4 address"
    echo ""
    echo "Examples:"
    echo "  $0 example.com all"
    echo "  $0 8.8.8.8 whois"
    echo "  $0 example.com reverse"
    exit 1
fi

TARGET=$1
MODE="${2:-all}"

if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
    if ! is_valid_ip "$TARGET" && ! is_valid_domain "$TARGET"; then
        echo "❌ Invalid target format: '$TARGET' (must be a valid IP or domain)"
        log_wr "❌ Invalid target provided: $TARGET"
        exit 1
    fi
fi

case "$MODE" in
    whois)
        whois_lookup "$TARGET"
        ;;
    reverse)
        reverse_dns_lookup "$TARGET"
        reverse_ip_co_hosts "$TARGET"
        ;;
    netrange)
        netrange_discovery "$TARGET"
        ;;
    all)
        run_all "$TARGET"
        ;;
    *)
        echo "Unknown mode: $MODE"
        exit 1
        ;;
esac

echo ""
echo "✅ WHOIS & reverse lookup complete!"
echo "📁 Results saved to: $WR_OUTPUT/"
echo "📋 Log file: $WR_LOG"
