#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - WHOIS & REVERSE LOOKUP RECONNAISSANCE MODULE
# WHOIS, reverse DNS, netrange extraction and related-domain discovery
# Philosophy: Map ownership and infrastructure ranges before scanning.
# ═══════════════════════════════════════════════════════════════════

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WHOIS_LOG="logs/whois_$TIMESTAMP.log"
WHOIS_OUTPUT="output/whois_$TIMESTAMP"

log_whois() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$WHOIS_LOG"
}

write_section() {
    local file=$1
    local title=$2
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "$title"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
    } | tee -a "$file"
}

# Resolve a domain to its A records (one per line)
resolve_ips() {
    local target=$1
    dig +short "$target" A 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u
}

# Extract an IP from a domain or return the IP as-is
primary_ip_from_target() {
    local target=$1
    if is_valid_ip "$target" 2>/dev/null; then
        echo "$target"
    else
        resolve_ips "$target" | head -1
    fi
}

# ─── WHOIS LOOKUP (DOMAIN) ───────────────────────────────────────
whois_domain_lookup() {
    local domain=$1
    log_whois "🔍 WHOIS lookup for domain: $domain"
    local output_file="$WHOIS_OUTPUT/whois_domain.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS LOOKUP: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        if command -v whois &>/dev/null; then
            whois "$domain" 2>/dev/null || echo "[!] WHOIS query failed for $domain"
        else
            echo "❌ whois command not found. Install with: sudo apt install whois"
        fi
    } | tee "$output_file"

    log_whois "✅ Domain WHOIS saved to $output_file"
}

# ─── WHOIS LOOKUP (IP) ───────────────────────────────────────────
whois_ip_lookup() {
    local ip=$1
    log_whois "🔍 WHOIS lookup for IP: $ip"
    local output_file="$WHOIS_OUTPUT/whois_ip.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS LOOKUP: $ip"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        if command -v whois &>/dev/null; then
            whois "$ip" 2>/dev/null || echo "[!] WHOIS query failed for $ip"
        else
            echo "❌ whois command not found. Install with: sudo apt install whois"
        fi
    } | tee "$output_file"

    log_whois "✅ IP WHOIS saved to $output_file"
}

# ─── REVERSE DNS (PTR) LOOKUP ────────────────────────────────────
reverse_dns_lookup() {
    local target=$1
    log_whois "🔍 Reverse DNS lookup for: $target"
    local output_file="$WHOIS_OUTPUT/reverse_dns.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "REVERSE DNS (PTR) LOOKUP: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        local ips
        if is_valid_ip "$target" 2>/dev/null; then
            ips=("$target")
        else
            mapfile -t ips < <(resolve_ips "$target")
        fi

        if [[ ${#ips[@]} -eq 0 ]]; then
            echo "[!] Could not resolve $target to an IP address"
        fi

        for ip in "${ips[@]}"; do
            echo "Target IP: $ip"
            echo "────────────────────────────────────────────────────────────────"
            local ptr
            ptr=$(dig -x "$ip" +short 2>/dev/null)
            if [[ -n "$ptr" ]]; then
                echo "PTR record: $ptr"
            else
                echo "No PTR record found"
            fi
            echo ""
        done
    } | tee "$output_file"

    log_whois "✅ Reverse DNS results saved to $output_file"
}

# ─── IP RANGE / NETBLOCK EXTRACTION ──────────────────────────────
ip_range_extraction() {
    local target=$1
    log_whois "🔍 Extracting IP ranges/netblocks for: $target"
    local output_file="$WHOIS_OUTPUT/ip_ranges.txt"

    local ip
    ip=$(primary_ip_from_target "$target")

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "IP RANGES & NETBLOCKS: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if [[ -z "$ip" ]]; then
            echo "[!] Could not resolve $target to an IP address"
            return
        fi

        echo "Resolved IP: $ip"
        echo ""

        if command -v whois &>/dev/null; then
            echo "📊 WHOIS netblock information:"
            echo "────────────────────────────────────────────────────────────────"
            local whois_data
            whois_data=$(whois "$ip" 2>/dev/null || true)

            echo "$whois_data" | grep -iE '^(inetnum|netrange|cidr|route|origin|aut-num|orgname|org-name|netname|descr|organization|city|country)' || true

            echo ""
            echo "📊 Parsed CIDR / NetRange blocks:"
            echo "────────────────────────────────────────────────────────────────"
            echo "$whois_data" | grep -iE '^cidr' | awk -F':' '{print $2}' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sort -u || true
            echo "$whois_data" | grep -iE '^inetnum' | sed -E 's/^[Ii]netnum:[[:space:]]*//' || true
            echo "$whois_data" | grep -iE '^netrange' | sed -E 's/^[Nn]etrange:[[:space:]]*//' || true
        else
            echo "❌ whois command not found. Install with: sudo apt install whois"
        fi
    } | tee "$output_file"

    log_whois "✅ IP ranges saved to $output_file"
}

# ─── RELATED DOMAINS / SHARED HOSTING DISCOVERY ──────────────────
related_domains_lookup() {
    local target=$1
    log_whois "🔍 Finding related domains / shared hosting for: $target"
    local output_file="$WHOIS_OUTPUT/related_domains.txt"

    local ip
    ip=$(primary_ip_from_target "$target")

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "RELATED DOMAINS / SHARED HOSTING: $target"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if [[ -z "$ip" ]]; then
            echo "[!] Could not resolve $target to an IP address"
            return
        fi

        echo "Resolved IP: $ip"
        echo ""

        if command -v curl &>/dev/null; then
            echo "📊 Reverse IP lookup (passive, via HackerTarget API):"
            echo "────────────────────────────────────────────────────────────────"
            local reverse_result
            reverse_result=$(curl -s --max-time 20 "https://api.hackertarget.com/reverseiplookup/?q=$ip" 2>/dev/null || true)
            if [[ -n "$reverse_result" && "$reverse_result" != *"error"* && "$reverse_result" != *"No DNS"* ]]; then
                echo "$reverse_result" | sort -u
                echo ""
                echo "Count: $(echo "$reverse_result" | grep -cE '^[a-zA-Z0-9]' || echo 0) domains"
            else
                echo "No related domains found or API limit reached."
                echo "$reverse_result"
            fi

            echo ""
            echo "📊 ASN / Organization lookup (passive, via HackerTarget API):"
            echo "────────────────────────────────────────────────────────────────"
            local asn_result
            asn_result=$(curl -s --max-time 20 "https://api.hackertarget.com/aslookup/?q=$ip" 2>/dev/null || true)
            if [[ -n "$asn_result" && "$asn_result" != *"error"* ]]; then
                echo "$asn_result"
            else
                echo "No ASN data returned or API limit reached."
            fi
        else
            echo "❌ curl command not found. Reverse lookups require curl."
        fi

        echo ""
        echo "💡 Tip: Use the CIDR blocks from ip_ranges.txt to scan the entire netblock."
    } | tee "$output_file"

    log_whois "✅ Related domains saved to $output_file"
}

# ─── SUMMARY ─────────────────────────────────────────────────────
generate_summary() {
    local target=$1
    local output_file="$WHOIS_OUTPUT/summary.txt"
    local primary
    primary=$(primary_ip_from_target "$target")

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "WHOIS & REVERSE LOOKUP SUMMARY"
        echo "Target: $target"
        echo "Primary IP: ${primary:-N/A}"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Output files:"
        ls -1 "$WHOIS_OUTPUT" 2>/dev/null | sed 's/^/  • /'
        echo ""
        echo "Next steps:"
        echo "  1. Review ip_ranges.txt for CIDR/netblocks to scan."
        echo "  2. Review related_domains.txt for co-hosted targets."
        echo "  3. Feed discovered IP ranges into option 2 (Scan Specific Host) or option 5 (Batch)."
    } | tee "$output_file"

    log_whois "✅ Summary saved to $output_file"
}

# ─── MAIN ────────────────────────────────────────────────────────
TARGET="${1:-}"
MODE="${2:-all}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <domain-or-ip> [domain|ip|reverse|ranges|related|all]"
    exit 1
fi

if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
    if ! is_valid_ip "$TARGET" && ! is_valid_domain "$TARGET"; then
        echo "❌ Invalid target format. Must be a valid IP address or domain name."
        echo "🛑 Aborting without running any scan. No output saved."
        exit 1
    fi
fi

mkdir -p logs output "$WHOIS_OUTPUT"

log_whois "🎯 WHOIS & Reverse Lookup module initialized for: $TARGET (mode: $MODE)"

case "$MODE" in
    domain)
        whois_domain_lookup "$TARGET"
        ;;
    ip)
        if is_valid_ip "$TARGET" 2>/dev/null; then
            whois_ip_lookup "$TARGET"
        else
            echo "[!] 'ip' mode requires an IP address, not a domain"
            exit 1
        fi
        ;;
    reverse)
        reverse_dns_lookup "$TARGET"
        ;;
    ranges)
        ip_range_extraction "$TARGET"
        ;;
    related)
        related_domains_lookup "$TARGET"
        ;;
    all)
        if is_valid_domain "$TARGET" 2>/dev/null; then
            whois_domain_lookup "$TARGET"
        fi
        ip=$(primary_ip_from_target "$TARGET")
        if [[ -n "$ip" ]]; then
            whois_ip_lookup "$ip"
            reverse_dns_lookup "$TARGET"
            ip_range_extraction "$TARGET"
            related_domains_lookup "$TARGET"
        else
            echo "[!] Could not resolve $TARGET to an IP; skipping IP-based lookups"
        fi
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 <domain-or-ip> [domain|ip|reverse|ranges|related|all]"
        exit 1
        ;;
esac

generate_summary "$TARGET"

echo ""
echo "✅ WHOIS & Reverse Lookup recon complete!"
echo "📁 Results saved to: $WHOIS_OUTPUT/"
echo "📋 Session log: $WHOIS_LOG"
log_whois "🏁 WHOIS & Reverse Lookup recon complete. Results in $WHOIS_OUTPUT/"
