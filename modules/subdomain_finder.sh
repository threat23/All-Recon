#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - SUBDOMAIN DISCOVERY MODULE
# Comprehensive subdomain enumeration & reconnaissance
# Philosophy: Find all the hidden doors before you start knocking
# ═══════════════════════════════════════════════════════════════════

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

SUBDOMAIN_LOG="logs/subdomain_$(date +%Y%m%d_%H%M%S).log"
SUBDOMAIN_OUTPUT="output/subdomains_$(date +%Y%m%d_%H%M%S)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p logs output

log_subdomain() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$SUBDOMAIN_LOG"
}

# Function: DNS enumeration
dns_subdomain_enum() {
    local domain=$1
    log_subdomain "[SCAN] Starting DNS subdomain enumeration on $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/dns_enum_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "DNS SUBDOMAIN ENUMERATION: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        # Attempt zone transfer
        echo "[SCAN] Attempting Zone Transfer..."
        echo "────────────────────────────────────────────────────────────────"
        for ns in $(dig +short NS "$domain"); do
            echo "Trying $ns..."
            dig @"$ns" "$domain" AXFR 2>/dev/null || echo "No zone transfer available"
        done
        
        echo ""
        echo "[SCAN] Reverse DNS Lookup..."
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" +nocmd +noall +answer | while read -r line; do
            ip=$(echo "$line" | awk '{print $NF}')
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "IP: $ip"
                dig -x "$ip" +short 2>/dev/null || echo "  (no reverse DNS)"
            fi
        done
        
        echo ""
        echo "[SCAN] Common DNS Records..."
        echo "────────────────────────────────────────────────────────────────"
        for record in A AAAA MX NS TXT SPF CNAME; do
            echo ""
            echo "[$record Records]"
            dig "$domain" "$record" +noall +answer 2>/dev/null || echo "No $record records"
        done
        
    } | tee "$output_file"
    
    log_subdomain "[OK] DNS enumeration complete"
}

# Function: Common subdomains brute force
common_subdomains_bruteforce() {
    local domain=$1
    log_subdomain "[SCAN] Brute-forcing common subdomains on $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/common_subdomains_$TIMESTAMP.txt"
    
    # Common subdomain list
    local subdomains=(
        "www" "mail" "ftp" "localhost" "webmail" "smtp" "pop" "ns1" "webdisk"
        "ns2" "cpanel" "whois" "autodiscover" "autoconfig" "m" "imap" "test"
        "portal" "ns" "vpn" "api" "staging" "dev" "development" "stage"
        "admin" "administrator" "backup" "cdn" "files" "s3" "storage"
        "blog" "shop" "app" "apps" "db" "database" "sql" "server"
        "mail2" "mail3" "secure" "secure2" "pop3" "imap4" "outlook"
        "web" "srv" "svc" "git" "repo" "svn" "monitor" "monitoring"
        "dns" "dns1" "dns2" "internal" "intranet" "proxy"
        "cache" "search" "download" "downloads" "support" "help"
        "kb" "knowledge" "wiki" "forum" "community" "chat" "slack"
        "status" "health" "metrics" "prometheus" "grafana" "logs"
        "elastic" "kibana" "jenkins" "travis" "ci" "cd" "deploy"
    )
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "COMMON SUBDOMAIN BRUTE FORCE: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Testing ${#subdomains[@]} common subdomains..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        
        local found_count=0
        
        for sub in "${subdomains[@]}"; do
            target="$sub.$domain"
            result=$(dig +short "$target" A 2>/dev/null | grep -v "^$")
            
            if [[ -n "$result" ]]; then
                echo "[OK] FOUND: $target"
                echo "   IP: $result"
                ((found_count++))
            fi
        done
        
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo "Summary: Found $found_count subdomains"
        
    } | tee "$output_file"
    
    log_subdomain "[OK] Brute force complete - found subdomains"
}

# Function: Reverse IP lookup
reverse_ip_lookup() {
    local domain=$1
    log_subdomain "[SCAN] Performing reverse IP lookup for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/reverse_ip_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "REVERSE IP LOOKUP: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        # Get primary IP
        primary_ip=$(dig +short "$domain" A | head -1)
        
        if [[ -n "$primary_ip" ]]; then
            echo "Primary IP: $primary_ip"
            echo ""
            echo "Reverse DNS:"
            dig -x "$primary_ip" +short
            
            echo ""
            echo "Same IP hosting (potential subdomains):"
            # Try to find other subdomains on same IP
            nslookup "$domain" 2>/dev/null | grep "Name:" -A1 | tail -1
        else
            echo "Could not resolve domain to IP"
        fi
        
    } | tee "$output_file"
    
    log_subdomain "[OK] Reverse IP lookup complete"
}

# Function: Public DNS records scan
public_dns_scan() {
    local domain=$1
    log_subdomain "[SCAN] Scanning public DNS records for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/dns_records_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "PUBLIC DNS RECORDS SCAN: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        echo "[REPORT] A Records (IPv4):"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" A +noall +answer
        
        echo ""
        echo "[REPORT] AAAA Records (IPv6):"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" AAAA +noall +answer
        
        echo ""
        echo "[REPORT] CNAME Records:"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" CNAME +noall +answer
        
        echo ""
        echo "[REPORT] MX Records (Mail Servers):"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" MX +noall +answer
        
        echo ""
        echo "[REPORT] NS Records (Name Servers):"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" NS +noall +answer
        
        echo ""
        echo "[REPORT] TXT Records:"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" TXT +noall +answer
        
        echo ""
        echo "[REPORT] SOA Records:"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" SOA +noall +answer
        
        echo ""
        echo "[REPORT] SRV Records:"
        echo "────────────────────────────────────────────────────────────────"
        dig "$domain" SRV +noall +answer
        
    } | tee "$output_file"
    
    log_subdomain "[OK] DNS records scan complete"
}

# Function: HTTPS certificate scanning (if available)
cert_transparency_scan() {
    local domain=$1
    log_subdomain "[SCAN] Scanning certificate transparency logs for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/cert_transparency_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "CERTIFICATE TRANSPARENCY: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        echo "Using crt.sh API for Certificate Transparency logs..."
        echo "────────────────────────────────────────────────────────────────"
        
        # Query crt.sh for SSL certificates
        curl -s "https://crt.sh/?q=%25.$domain&output=json" 2>/dev/null | \
        grep -oP '"common_name":"[^"]*"' | cut -d'"' -f4 | sort -u | grep -v "^$" || \
        echo "Could not reach crt.sh or no results found"
        
        echo ""
        echo "[TIP] Tip: Visit https://crt.sh for web interface"
        
    } | tee "$output_file"
    
    log_subdomain "[OK] Certificate transparency scan complete"
}

# Function: HackerTarget OSINT lookup
hackertarget_osint_scan() {
    local domain=$1
    log_subdomain "[SCAN] Querying HackerTarget API for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/hackertarget_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "HACKERTARGET OSINT DISCOVERY: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        resp=$(curl -s --max-time 15 "https://api.hackertarget.com/hostsearch/?q=$domain" 2>/dev/null)
        if [[ -n "$resp" && ! "$resp" =~ "error" && ! "$resp" =~ "API count exceeded" ]]; then
            echo "$resp" | cut -d',' -f1 | sort -u | grep -v "^$"
        else
            echo "HackerTarget API unavailable or rate limited"
        fi
    } | tee "$output_file"
    
    log_subdomain "[OK] HackerTarget OSINT scan complete"
}

# Function: AlienVault OTX Passive DNS lookup
alienvault_osint_scan() {
    local domain=$1
    log_subdomain "[SCAN] Querying AlienVault OTX Passive DNS for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/alienvault_otx_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "ALIENVULT OTX OSINT DISCOVERY: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        resp=$(curl -s --max-time 15 "https://otx.alienvault.com/api/v1/indicators/domain/$domain/passive_dns" 2>/dev/null)
        if [[ -n "$resp" ]]; then
            echo "$resp" | grep -oP '"hostname":"[^"]+"' | cut -d'"' -f4 | grep "\.$domain$" | sort -u | grep -v "^$" || echo "No AlienVault records found"
        else
            echo "AlienVault OTX API unavailable"
        fi
    } | tee "$output_file"
    
    log_subdomain "[OK] AlienVault OTX OSINT scan complete"
}

# Function: RapidDNS lookup
rapiddns_osint_scan() {
    local domain=$1
    log_subdomain "[SCAN] Querying RapidDNS for $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/rapiddns_$TIMESTAMP.txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "RAPIDDNS OSINT DISCOVERY: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        resp=$(curl -s --max-time 15 "https://rapiddns.io/subdomain/$domain?full=1" 2>/dev/null)
        if [[ -n "$resp" ]]; then
            echo "$resp" | grep -oP '(?<=<td>)[a-zA-Z0-9.-]+\.'"$domain"'(?=</td>)' | sort -u | grep -v "^$" || \
            echo "$resp" | grep -oP '[a-zA-Z0-9.-]+\.'"$domain" | sort -u | grep -v "^$" || \
            echo "No RapidDNS records found"
        else
            echo "RapidDNS unavailable"
        fi
    } | tee "$output_file"
    
    log_subdomain "[OK] RapidDNS OSINT scan complete"
}

# Function: Aggregated Passive OSINT scan
passive_osint_scan() {
    local domain=$1
    log_subdomain "[SCAN] Starting Aggregated Passive OSINT discovery on $domain..."
    
    mkdir -p "$SUBDOMAIN_OUTPUT"
    output_file="$SUBDOMAIN_OUTPUT/passive_osint_$TIMESTAMP.txt"
    
    cert_transparency_scan "$domain"
    hackertarget_osint_scan "$domain"
    alienvault_osint_scan "$domain"
    rapiddns_osint_scan "$domain"
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "AGGREGATED PASSIVE OSINT DISCOVERY: $domain"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Combined findings from crt.sh, HackerTarget, AlienVault OTX, RapidDNS:"
        echo "────────────────────────────────────────────────────────────────"
        
        grep -hE "^[a-zA-Z0-9.-]+\.${domain//./\.}$" "$SUBDOMAIN_OUTPUT"/*.txt 2>/dev/null | sort -u | grep -v "^$" || \
        grep -h "FOUND:" "$SUBDOMAIN_OUTPUT"/*.txt 2>/dev/null | awk '{print $NF}' | sort -u
    } | tee "$output_file"
    
    log_subdomain "[OK] Passive OSINT discovery complete"
}

# Function: Comprehensive scan (all methods)
comprehensive_subdomain_scan() {
    local domain=$1
    log_subdomain "[SCAN] Starting COMPREHENSIVE subdomain scan on $domain..."
    log_subdomain "This may take a few minutes..."
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "[TARGET] COMPREHENSIVE SUBDOMAIN DISCOVERY"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    dns_subdomain_enum "$domain"
    echo ""
    
    common_subdomains_bruteforce "$domain"
    echo ""
    
    reverse_ip_lookup "$domain"
    echo ""
    
    public_dns_scan "$domain"
    echo ""
    
    passive_osint_scan "$domain"
    
    # Generate summary
    mkdir -p "$SUBDOMAIN_OUTPUT"
    summary_file="$SUBDOMAIN_OUTPUT/summary_$TIMESTAMP.txt"
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "SUBDOMAIN DISCOVERY SUMMARY"
        echo "Domain: $domain"
        echo "Date: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Files generated:"
        ls -1 "$SUBDOMAIN_OUTPUT"/ | sed 's/^/  /'
        echo ""
    } | tee "$summary_file"
    
    log_subdomain "[OK] Comprehensive scan complete"
}

# Main execution
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <domain> <scan_type>"
    echo ""
    echo "Scan types:"
    echo "  dns              - DNS zone transfer & enumeration"
    echo "  common           - Common subdomain brute force"
    echo "  reverse          - Reverse IP lookup"
    echo "  records          - Public DNS records scan"
    echo "  cert             - Certificate transparency logs"
    echo "  hackertarget     - HackerTarget OSINT API"
    echo "  alienvault       - AlienVault OTX Passive DNS"
    echo "  rapiddns         - RapidDNS subdomain lookup"
    echo "  osint            - Aggregated Passive OSINT (crt.sh + APIs)"
    echo "  all              - Comprehensive scan (all methods)"
    echo ""
    echo "Examples:"
    echo "  $0 example.com all"
    echo "  $0 example.com osint"
    echo "  $0 example.com hackertarget"
    exit 1
fi

DOMAIN=$1
SCAN_TYPE=$2

if type is_valid_domain &>/dev/null; then
    if ! is_valid_domain "$DOMAIN"; then
        echo "[ERROR] Invalid domain format: '$DOMAIN'"
        log_subdomain "[ERROR] Invalid domain provided: $DOMAIN"
        exit 1
    fi
fi

case $SCAN_TYPE in
    dns)
        dns_subdomain_enum "$DOMAIN"
        ;;
    common)
        common_subdomains_bruteforce "$DOMAIN"
        ;;
    reverse)
        reverse_ip_lookup "$DOMAIN"
        ;;
    records)
        public_dns_scan "$DOMAIN"
        ;;
    cert)
        cert_transparency_scan "$DOMAIN"
        ;;
    hackertarget)
        hackertarget_osint_scan "$DOMAIN"
        ;;
    alienvault)
        alienvault_osint_scan "$DOMAIN"
        ;;
    rapiddns)
        rapiddns_osint_scan "$DOMAIN"
        ;;
    osint)
        passive_osint_scan "$DOMAIN"
        ;;
    all)
        comprehensive_subdomain_scan "$DOMAIN"
        ;;
    *)
        echo "Unknown scan type: $SCAN_TYPE"
        exit 1
        ;;
esac

echo ""
echo "[OK] Subdomain discovery complete!"
echo "[DIR] Results saved to: $SUBDOMAIN_OUTPUT/"
echo "[LIST] Log file: $SUBDOMAIN_LOG"

