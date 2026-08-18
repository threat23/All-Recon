#!/bin/bash

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

RECON_LOG="logs/recon_$(date +%Y%m%d_%H%M%S).log"
RECON_OUTPUT="output/recon_$(date +%Y%m%d_%H%M%S)"

mkdir -p logs output "$RECON_OUTPUT"

log_recon() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$RECON_LOG"
}

# Function: DNS Reconnaissance
dns_recon() {
    local target=$1
    log_recon "[SCAN] Starting DNS reconnaissance on $target..."
    
    mkdir -p "$RECON_OUTPUT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/dns.txt"
    echo "DNS RECONNAISSANCE: $target" | tee -a "$RECON_OUTPUT/dns.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/dns.txt"
    
    # DNS lookup
    nslookup "$target" | tee -a "$RECON_OUTPUT/dns.txt"
    
    # MX records
    echo "" | tee -a "$RECON_OUTPUT/dns.txt"
    echo "MX RECORDS:" | tee -a "$RECON_OUTPUT/dns.txt"
    dig MX "$target" +short | tee -a "$RECON_OUTPUT/dns.txt"
    
    # NS records
    echo "" | tee -a "$RECON_OUTPUT/dns.txt"
    echo "NAMESERVERS:" | tee -a "$RECON_OUTPUT/dns.txt"
    dig NS "$target" +short | tee -a "$RECON_OUTPUT/dns.txt"
    
    # TXT records
    echo "" | tee -a "$RECON_OUTPUT/dns.txt"
    echo "TXT RECORDS:" | tee -a "$RECON_OUTPUT/dns.txt"
    dig TXT "$target" +short | tee -a "$RECON_OUTPUT/dns.txt"
    
    log_recon "[OK] DNS reconnaissance complete"
}

# Function: Whois Information
whois_recon() {
    local target=$1
    log_recon "[SCAN] Gathering WHOIS information for $target..."
    
    mkdir -p "$RECON_OUTPUT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/whois.txt"
    echo "WHOIS INFORMATION: $target" | tee -a "$RECON_OUTPUT/whois.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/whois.txt"
    
    whois "$target" 2>/dev/null | tee -a "$RECON_OUTPUT/whois.txt" || echo "WHOIS tool not available"
    
    log_recon "[OK] WHOIS reconnaissance complete"
}

# Function: Port Service Mapping
service_mapping() {
    local target=$1
    log_recon "[SCAN] Mapping services on $target..."
    
    mkdir -p "$RECON_OUTPUT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/services.txt"
    echo "SERVICE MAPPING: $target" | tee -a "$RECON_OUTPUT/services.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$RECON_OUTPUT/services.txt"
    
    nmap -sV -T4 --top-ports 1000 "$target" | tee -a "$RECON_OUTPUT/services.txt"
    
    log_recon "[OK] Service mapping complete"
}

# Main execution
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <target> <recon_type>"
    echo "Recon types: dns, whois, services, all"
    exit 1
fi

TARGET=$1
RECON_TYPE=$2

if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
    if ! is_valid_ip "$TARGET" && ! is_valid_domain "$TARGET"; then
        echo "[ERROR] Invalid target format (must be valid IP or Domain): '$TARGET'"
        log_recon "[ERROR] Invalid target provided: $TARGET"
        exit 1
    fi
fi

mkdir -p "$RECON_OUTPUT"

case $RECON_TYPE in
    dns)
        dns_recon "$TARGET"
        ;;
    whois)
        whois_recon "$TARGET"
        ;;
    services)
        service_mapping "$TARGET"
        ;;
    all)
        dns_recon "$TARGET"
        whois_recon "$TARGET"
        service_mapping "$TARGET"
        ;;
    *)
        echo "Unknown recon type: $RECON_TYPE"
        exit 1
        ;;
esac

echo ""
echo "[OK] Reconnaissance complete!"
echo "[DIR] Results saved to: $RECON_OUTPUT/"
echo "[LIST] Log file: $RECON_LOG"

