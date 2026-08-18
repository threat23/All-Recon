#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - PENTESTER WORKFLOW AUTOMATION SUITE
# Philosophy: Automate boring tasks. Focus on interesting findings.
# ═══════════════════════════════════════════════════════════════════

# Setup directories
OUTPUT_DIR="output"
LOGS_DIR="logs"
mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/modules/validation.sh" ]]; then
    source "$SCRIPT_DIR/modules/validation.sh"
    setup_signal_traps
fi

# Timestamp for organized output
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_LOG="$LOGS_DIR/session_$TIMESTAMP.log"

# ─── GLORIOUS BANNER ────────────────────────────────────────
clear

# Dependency checks
for cmd in toilet lolcat; do
    command -v "$cmd" &>/dev/null || {
        echo "[ERROR] $cmd is not installed. Install it first."
        [[ $cmd == "lolcat" ]] && echo "    sudo gem install lolcat"
        [[ $cmd == "toilet" ]] && echo "    sudo apt install toilet"
        exit 1
    }
done

# Function to log output
log_output() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$SESSION_LOG"
}

# Decorative bar
bar="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Tagline pool
taglines=(
  "Humphrey Chile | THREAT | ALL-RECON | & JOSH "
  "Elite Recon Suite | Code Red Ops | Threat Intelligence Division"
  "Scan Deep. Strike Hard. Vanish Clean."
  "Surveillance Is Tactical. Silence Is Survival."
  "Built for Hackers, Hardened for Warzones."
  "Your Perimeter Just Became My Playground."
  "Recon. Exploit. Report. Repeat."
)

# Select random tagline
tagline=${taglines[$RANDOM % ${#taglines[@]}]}

# Show banner
echo "$bar" | lolcat
toilet -f big "ALL-RECON" --metal | lolcat
echo "$bar" | lolcat
echo -e "\e[1;37m$tagline\e[0m" | lolcat
echo ""

# ─── LOADING FX ──────────────────────────────────────────────
echo -ne "$(tput bold)-> Initializing ALL-RECON Scan Engine...$(tput sgr0)"
for i in {1..8}; do echo -ne "."; sleep 0.15; done
echo -e "\n"

progress=""
max=30
echo -ne "$(tput bold)[LOAD] Charging payload modules: [$(tput sgr0)"
for ((i=1; i<=max; i++)); do
    percent=$((i * 100 / max))
    color=$((31 + RANDOM % 7))
    progress+=$(tput setaf $color)█$(tput sgr0)
    echo -ne "\r$(tput bold)[LOAD] Charging payload modules: [${progress}$(tput bold)] $percent%$(tput sgr0)"
    sleep 0.07
done
echo -e "\n"

echo -ne "$(tput bold)[OBSERVE]  Acquiring live targets"
for dot in {1..10}; do
    echo -ne "$(tput setaf $((30 + dot % 7))).$(tput sgr0)"; sleep 0.1
done
echo -e "\n$(tput bold)[+] Target lock confirmed.$(tput sgr0)"
echo ""

# ─── IP DETECTION ──────────────────────────────────────────────
internal_ip=$(hostname -I | awk '{print $1}')
external_ip=$(curl -s ifconfig.me)
if [[ -z "$external_ip" ]]; then
    external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
fi
echo ""
echo -e "$(tput bold)[IP] Internal IP  : $internal_ip$(tput sgr0)"
echo -e "$(tput bold)[IP] External IP  : $external_ip$(tput sgr0)"
echo ""

# ─── MAIN MENU ─────────────────────────────────────────────
echo "Select Scan Type:"
echo "1. Local Network Scan (Ping Sweep + Port Scan)"
echo "2. Scan Specific Host (Website IP or Domain)"
echo "3. Subdomain Discovery & Enumeration"
echo "4. Web Vulnerability Scan"
echo "5. Multi-Target Batch Scanner (Process target list file)"
echo "6. WHOIS & Reverse Lookup Recon"
echo "7. Passive OSINT (crt.sh, Wayback, RDAP)"
echo "8. View Last Results"
echo "9. Generate Report"
echo "10. Exit / Cancel"
read -p "Enter choice [1/2/3/4/5/6/7/8/9/10]: " choice
echo ""

# ─── HANDLE USER CHOICE ─────────────────────────────────────
if [[ "$choice" == "1" ]]; then
    subnet=$(ip -4 addr show | grep -oP '(?<=inet\s)(?!127)\d+\.\d+\.\d+' | head -1)
    if [[ -z "$subnet" ]]; then
        echo "[ERROR] Could not auto-detect subnet. Please check network interface."
        exit 1
    fi
    echo "[*] Scanning subnet: $subnet.0/24"
    log_output "[SCAN] Local network scan initiated on $subnet.0/24"
    tmpfile=$(mktemp)
    if type register_tmp_file &>/dev/null; then register_tmp_file "$tmpfile"; fi
    scan_output="$OUTPUT_DIR/network_scan_$TIMESTAMP.txt"

    for i in {1..254}; do
        ip="$subnet.$i"
        (ping -c 1 -W 1 "$ip" &> /dev/null && echo "$ip" >> "$tmpfile") &
    done
    wait

    if [[ -s $tmpfile ]]; then
        echo "[+] Hosts up:"
        cat "$tmpfile" | tee -a "$scan_output"
        echo ""
        echo -e "$(tput setaf 3)[WARN]  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
        log_output "[OK] Discovered active hosts. Starting detailed port scan..."
        echo "[*] Starting full nmap scans..."
        
        while read -r ip; do
            echo "[SCAN] Scanning $ip ..."
            nmap_output="$OUTPUT_DIR/host_${ip//./_}_$TIMESTAMP.txt"
            nmap -sS -O --osscan-guess --osscan-limit --max-os-tries 1 -T4 -Pn -p- "$ip" | tee "$nmap_output"
            log_output "[OK] Scan complete for $ip (results: $nmap_output)"
            echo ""
        done < "$tmpfile"
    else
        echo "[*] No Host was up."
        log_output "[WARN] No active hosts discovered in subnet"
    fi
    rm -f "$tmpfile"

elif [[ "$choice" == "2" ]]; then
    read -p "Enter the target IP or domain: " target
    if [[ -z "$target" ]]; then
        echo "[ERROR] Target cannot be empty"
        exit 1
    fi
    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target" && ! is_valid_domain "$target"; then
            echo "[ERROR] Invalid target format. Must be a valid IP address or domain name."
            log_output "[ERROR] Invalid target provided: $target"
            exit 1
        fi
    fi
    echo -e "$(tput setaf 3)[WARN]  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    log_output "[SCAN] Targeted scan initiated on $target"
    echo "[SCAN] Scanning $target ..."
    nmap_output="$OUTPUT_DIR/host_${target//[^a-zA-Z0-9]/_}_$TIMESTAMP.txt"
    nmap -sS -O --osscan-guess --osscan-limit --max-os-tries 1 -T4 -Pn -p- "$target" | tee "$nmap_output"
    log_output "[OK] Scan complete for $target (results: $nmap_output)"

elif [[ "$choice" == "3" ]]; then
    echo "[SCAN] Subdomain Discovery Workflow:"
    echo "1. Run Subdomain Discovery"
    echo "2. Clean & Deduplicate Results"
    echo "3. View Cleaned Results"
    read -p "Select action [1/2/3]: " subdomain_action
    
    case $subdomain_action in
        1)
            read -p "Enter the target domain (e.g., example.com): " target_domain
            
            if [[ -z "$target_domain" ]]; then
                echo "[!] Domain cannot be empty"
                exit 1
            fi
            
            echo ""
            echo "[SCAN] Subdomain Discovery Methods:"
            echo "1. DNS Enumeration"
            echo "2. Common Subdomains (Brute Force)"
            echo "3. Reverse IP Lookup"
            echo "4. Public DNS Records"
            echo "5. Certificate Transparency (crt.sh)"
            echo "6. Aggregated Passive OSINT (crt.sh + HackerTarget + AlienVault + RapidDNS)"
            echo "7. Comprehensive (All Methods)"
            read -p "Select scan type [1/2/3/4/5/6/7]: " subdomain_choice
            
            case $subdomain_choice in
                1)
                    log_output "[SCAN] DNS enumeration initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" dns
                    ;;
                2)
                    log_output "[SCAN] Subdomain brute force initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" common
                    ;;
                3)
                    log_output "[SCAN] Reverse IP lookup initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" reverse
                    ;;
                4)
                    log_output "[SCAN] DNS records scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" records
                    ;;
                5)
                    log_output "[SCAN] Certificate transparency scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" cert
                    ;;
                6)
                    log_output "[SCAN] Aggregated Passive OSINT scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" osint
                    ;;
                7)
                    log_output "[SCAN] Comprehensive subdomain discovery initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" all
                    ;;
                *)
                    echo "[!] Invalid choice"
                    exit 1
                    ;;
            esac
            echo ""
            echo "[OK] Subdomain discovery complete!"
            echo "[DIR] Results saved to: output/subdomains_*/"
            echo ""
            read -p "Would you like to clean the results now? (y/n): " clean_now
            if [[ "$clean_now" =~ ^[Yy]$ ]]; then
                latest_subdomain_dir=$(ls -dt output/subdomains_*/ 2>/dev/null | head -1)
                if [[ -n "$latest_subdomain_dir" ]]; then
                    log_output "[CLEAN] Cleaning subdomain results from $latest_subdomain_dir"
                    bash modules/subdomain_cleaner.sh "$latest_subdomain_dir" all
                fi
            fi
            ;;
        2)
            echo ""
            echo "[DIR] Available subdomain discovery results:"
            ls -dt output/subdomains_*/ 2>/dev/null | head -5 || echo "No subdomain results found"
            echo ""
            read -p "Enter full path to subdomain results directory: " subdom_dir
            
            if [[ -d "$subdom_dir" ]]; then
                log_output "[CLEAN] Cleaning subdomain results from $subdom_dir"
                echo ""
                echo "[CLEAN] Cleaning Options:"
                echo "1. Extract unique subdomains"
                echo "2. Deduplicate and resolve IPs"
                echo "3. Filter active hosts only"
                echo "4. Group by IP address"
                echo "5. Export to CSV"
                echo "6. Export to JSON"
                echo "7. Comprehensive cleaning (all steps)"
                read -p "Select cleaning action [1/2/3/4/5/6/7]: " clean_choice
                
                case $clean_choice in
                    1) bash modules/subdomain_cleaner.sh "$subdom_dir" extract ;;
                    2) bash modules/subdomain_cleaner.sh "$subdom_dir" deduplicate ;;
                    3) bash modules/subdomain_cleaner.sh "$subdom_dir" active ;;
                    4) bash modules/subdomain_cleaner.sh "$subdom_dir" group ;;
                    5) bash modules/subdomain_cleaner.sh "$subdom_dir" csv ;;
                    6) bash modules/subdomain_cleaner.sh "$subdom_dir" json ;;
                    7) bash modules/subdomain_cleaner.sh "$subdom_dir" all ;;
                    *) echo "[!] Invalid choice" ;;
                esac
            else
                echo "[!] Directory not found: $subdom_dir"
            fi
            ;;
        3)
            echo ""
            echo "[DIR] Available cleaned results:"
            ls -dt output/clean_subdomains_*/ 2>/dev/null | head -5 || echo "No cleaned results found"
            echo ""
            read -p "Enter cleaned results directory (or press Enter to skip): " clean_dir
            if [[ -n "$clean_dir" && -d "$clean_dir" ]]; then
                echo ""
                echo "[LIST] Cleaned Results Files:"
                ls -lh "$clean_dir" | tail -n +2 | awk '{print $9, "(" $5 ")"}'
            fi
            ;;
        *)
            echo "[!] Invalid action"
            exit 1
            ;;
    esac

elif [[ "$choice" == "4" ]]; then
    read -p "Enter the target URL (e.g., http://target.com): " target_url

    if [[ -z "$target_url" ]]; then
        echo "[!] URL cannot be empty"
        exit 1
    fi

    echo ""
    echo -e "$(tput setaf 3)[WARN]  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    log_output "[SCAN] Web vulnerability scan initiated for $target_url"

    bash modules/web_vulnerabilities.sh "$target_url"

    echo ""
    echo "[OK] Web vulnerability scan complete!"
    echo "[DIR] Results saved to: output/web_vulns_*/"
    log_output "[OK] Web vulnerability scan complete for $target_url"

elif [[ "$choice" == "5" ]]; then
    read -p "Enter path to target file (default: targets.txt): " target_file
    target_file=${target_file:-targets.txt}

    if [[ ! -f "$target_file" ]]; then
        echo "[ERROR] File '$target_file' not found."
        echo "[TIP] Tip: Create a file with one IP/domain per line (e.g., echo 'example.com' > targets.txt)"
        exit 1
    fi

    echo ""
    echo "Select Batch Scan Mode:"
    echo "1. Reconnaissance (DNS + WHOIS + Services)"
    echo "2. WHOIS & Reverse Lookup Recon"
    echo "3. Subdomain Discovery (Passive OSINT)"
    echo "4. Passive OSINT (crt.sh + Wayback + RDAP)"
    echo "5. Web Vulnerabilities"
    echo "6. Comprehensive Scan (All Modules)"
    read -p "Enter mode choice [1/2/3/4/5/6]: " batch_mode_choice

    case $batch_mode_choice in
        1) mode="recon" ;;
        2) mode="whois" ;;
        3) mode="subdomain" ;;
        4) mode="passive" ;;
        5) mode="web" ;;
        6) mode="all" ;;
        *) mode="recon" ;;
    esac

    read -p "Enter max parallel workers [1-10] (default: 5): " max_workers
    max_workers=${max_workers:-5}

    log_output "-> Initiating Multi-Target Batch Scan from $target_file (Mode: $mode, Workers: $max_workers)"
    bash modules/batch_runner.sh "$target_file" "$mode" "$max_workers"
    log_output "[OK] Multi-Target Batch Scan completed for $target_file"

elif [[ "$choice" == "6" ]]; then
    read -p "Enter target domain or IP (e.g., example.com or 8.8.8.8): " target_whois

    if [[ -z "$target_whois" ]]; then
        echo "[!] Target cannot be empty"
        exit 1
    fi

    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target_whois" && ! is_valid_domain "$target_whois"; then
            echo "[ERROR] Invalid target format. Must be a valid IP address or domain name."
            exit 1
        fi
    fi

    echo ""
    echo "[SCAN] WHOIS & Reverse Lookup Options:"
    echo "1. Domain WHOIS"
    echo "2. IP WHOIS"
    echo "3. Reverse DNS (PTR)"
    echo "4. IP Ranges / Netblocks"
    echo "5. Related Domains / Shared Hosting"
    echo "6. Run Everything"
    read -p "Select lookup type [1/2/3/4/5/6]: " whois_choice

    case "$whois_choice" in
        1) mode="domain" ;;
        2) mode="ip" ;;
        3) mode="reverse" ;;
        4) mode="ranges" ;;
        5) mode="related" ;;
        6) mode="all" ;;
        *)
            echo "[!] Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    echo -e "$(tput setaf 3)[WARN]  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    log_output "[SCAN] WHOIS & Reverse Lookup recon initiated for $target_whois (mode: $mode)"
    bash modules/whois_recon.sh "$target_whois" "$mode"

    echo ""
    echo "[OK] WHOIS & Reverse Lookup recon complete!"
    echo "[DIR] Results saved to: output/whois_*/"
    log_output "[OK] WHOIS & Reverse Lookup recon complete for $target_whois"

elif [[ "$choice" == "7" ]]; then
    read -p "Enter target domain or IP for passive OSINT (e.g., example.com): " target_passive

    if [[ -z "$target_passive" ]]; then
        echo "[!] Target cannot be empty"
        exit 1
    fi

    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target_passive" && ! is_valid_domain "$target_passive"; then
            echo "[ERROR] Invalid target format. Must be a valid IP address or domain name."
            exit 1
        fi
    fi

    echo ""
    echo -e "$(tput setaf 3)[WARN]  Passive OSINT queries may take a few seconds.$(tput sgr0)"
    log_output "[SCAN] Passive OSINT scan initiated for $target_passive"
    bash modules/passive.sh "$target_passive"

    echo ""
    echo "[OK] Passive OSINT completed!"
    echo "[DIR] Results saved to: output/passive_${target_passive//[^a-zA-Z0-9.-]/_}_*.json"
    log_output "[OK] Passive OSINT scan complete for $target_passive"

elif [[ "$choice" == "8" ]]; then
    echo "[DIR] Recent Scan Results:"
    echo ""
    if [[ -f "$OUTPUT_DIR"/*.txt ]]; then
        ls -lht "$OUTPUT_DIR"/*.txt 2>/dev/null | head -10
        echo ""
        read -p "Enter filename to view (or press Enter to skip): " viewfile
        if [[ -n "$viewfile" ]]; then
            less "$OUTPUT_DIR/$viewfile"
        fi
    else
        echo "[*] No scan results found yet."
    fi

elif [[ "$choice" == "9" ]]; then
    echo "[REPORT] Generating Report..."
    report_file="$OUTPUT_DIR/report_$TIMESTAMP.txt"
    {
        echo "═════════════════════════════════════════════════════════"
        echo "ALL-RECON - SCAN REPORT"
        echo "Generated: $(date)"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        echo "[DIR] Scans Available:"
        ls -1 "$OUTPUT_DIR"/*.txt 2>/dev/null | grep -v report || echo "No scans found"
        echo ""
        echo "Session Log: $SESSION_LOG"
        echo ""
        echo "═════════════════════════════════════════════════════════"
    } | tee "$report_file"
    echo ""
    echo "[OK] Report saved to: $report_file"
    log_output "[REPORT] Report generated: $report_file"

elif [[ "$choice" == "10" ]]; then
    echo -e "$(tput bold)[*] Exiting ALL-RECON Recon Engine. Stay unseen. [SAFE]$(tput sgr0)"
    log_output "[STOP] Session ended"
    exit 0

else
    echo -e "$(tput bold)[!] Invalid choice. Exiting.$(tput sgr0)"
    exit 1
fi

echo "[*] Scan complete."
log_output "[DONE] Workflow step complete. Results in $OUTPUT_DIR/"
echo ""
echo "[DIR] All results saved to: $OUTPUT_DIR/"
echo "[LIST] Session log: $SESSION_LOG"
