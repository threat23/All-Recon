#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - PENTESTER WORKFLOW AUTOMATION SUITE
# Philosophy: Automate boring tasks. Focus on interesting findings.
# ═══════════════════════════════════════════════════════════════════

# Setup directories
OUTPUT_DIR="output"
LOGS_DIR="logs"
mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source validation module if available
if [[ -f "$SCRIPT_DIR/modules/validation.sh" ]]; then
    source "$SCRIPT_DIR/modules/validation.sh"
    setup_signal_traps
fi

# Source configuration profiles if available
CONFIG_DIR="$SCRIPT_DIR/config"
if [[ -f "$CONFIG_DIR/nmap_profiles.conf" ]]; then
    source "$CONFIG_DIR/nmap_profiles.conf"
fi
if [[ -f "$CONFIG_DIR/automation_rules.conf" ]]; then
    source "$CONFIG_DIR/automation_rules.conf"
fi

# Pre-tuned Nmap profiles with defaults
PROFILE_QUICK=${PROFILE_QUICK:-"-T4 -p 1-1000 -sS"}
PROFILE_STANDARD=${PROFILE_STANDARD:-"-sS -O --osscan-guess --osscan-limit -T4 -p- -Pn"}
PROFILE_THOROUGH=${PROFILE_THOROUGH:-"-sS -sU -O --osscan-guess -T3 -A -p- --script default,discovery"}
PROFILE_STEALTH=${PROFILE_STEALTH:-"-T1 -Pn -p- -sS"}

# Timestamp for organized output
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_LOG="$LOGS_DIR/session_$TIMESTAMP.log"

# Function to log output
log_output() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$SESSION_LOG"
}

# CLI Flags
CLI_TARGET=""
CLI_MODE=""
CLI_PROFILE="standard"
QUIET=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t <target>       Target IP, domain, URL, or target file"
    echo "  -m <mode>         Scan mode: network, host, subdomain, web, batch, whois, passive, report"
    echo "  -p <profile>      Nmap profile: quick, standard, thorough, stealth (default: standard)"
    echo "  -o <output_dir>   Output directory (default: output)"
    echo "  -q                Quiet mode (suppress visual banner & animations for automation)"
    echo "  -h                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -t 192.168.1.50 -m host -p quick"
    echo "  $0 -t example.com -m subdomain"
    echo "  $0 -t http://example.com -m web"
    echo "  $0 -t targets.txt -m batch"
    echo "  $0 -q -m report"
    echo "  $0                (Interactive menu mode)"
    exit 0
}

while getopts "t:m:p:o:qh" opt; do
    case "$opt" in
        t) CLI_TARGET="$OPTARG" ;;
        m) CLI_MODE="$OPTARG" ;;
        p) CLI_PROFILE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG"; mkdir -p "$OUTPUT_DIR" ;;
        q) QUIET=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Resolve profile flags
resolve_nmap_flags() {
    local prof="${1:-standard}"
    case "$prof" in
        quick|fast) echo "$PROFILE_QUICK" ;;
        standard) echo "$PROFILE_STANDARD" ;;
        thorough|deep) echo "$PROFILE_THOROUGH" ;;
        stealth) echo "$PROFILE_STEALTH" ;;
        *) echo "$PROFILE_STANDARD" ;;
    esac
}
CURRENT_PROFILE_FLAGS=$(resolve_nmap_flags "$CLI_PROFILE")

# ─── GLORIOUS BANNER & VISUALS ──────────────────────────────
if [[ "$QUIET" != "true" ]]; then
    if [[ -z "$CLI_MODE" ]]; then
        clear
    fi

    # Check for banner tools (toilet / lolcat)
    for cmd in toilet lolcat; do
        command -v "$cmd" &>/dev/null || {
            echo "❌ $cmd is not installed. Install it first."
            [[ $cmd == "lolcat" ]] && echo "    sudo gem install lolcat"
            [[ $cmd == "toilet" ]] && echo "    sudo apt install toilet"
            exit 1
        }
    done

    # Decorative bar & tagline pool
    bar="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    taglines=(
      "Humphrey Chile | THREAT | ALL-RECON | & JOSH "
      "Elite Recon Suite | Code Red Ops | Threat Intelligence Division"
      "Scan Deep. Strike Hard. Vanish Clean."
      "Surveillance Is Tactical. Silence Is Survival."
      "Built for Hackers, Hardened for Warzones."
      "Your Perimeter Just Became My Playground."
      "Recon. Exploit. Report. Repeat."
    )
    tagline=${taglines[$RANDOM % ${#taglines[@]}]}

    echo "$bar" | lolcat
    toilet -f big "ALL-RECON" --metal | lolcat
    echo "$bar" | lolcat
    echo -e "\e[1;37m$tagline\e[0m" | lolcat
    echo ""

    # Snappy initialization
    echo -e "$(tput bold)🚀 Initializing ALL-RECON Scan Engine [Profile: $CLI_PROFILE]$(tput sgr0)"
    echo -e "$(tput bold)[+] Target lock confirmed.$(tput sgr0)\n"

    # ─── IP DETECTION ──────────────────────────────────────────────
    internal_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    if [[ -z "$external_ip" ]]; then
        external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    fi
    echo -e "$(tput bold)📡 Internal IP  : ${internal_ip:-N/A}$(tput sgr0)"
    echo -e "$(tput bold)🌐 External IP  : ${external_ip:-N/A}$(tput sgr0)\n"
fi

# ─── MODE DISPATCHER (CLI OR INTERACTIVE) ─────────────────────
if [[ -n "$CLI_MODE" ]]; then
    case "$CLI_MODE" in
        network|1) choice="1" ;;
        host|2) choice="2" ;;
        subdomain|3) choice="3" ;;
        web|4) choice="4" ;;
        batch|5) choice="5" ;;
        whois|6) choice="6" ;;
        passive|7) choice="7" ;;
        results|8) choice="8" ;;
        report|9) choice="9" ;;
        exit|10) choice="10" ;;
        *) echo "❌ Unknown mode: $CLI_MODE"; usage ;;
    esac
else
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
fi

# ─── HANDLE USER CHOICE ─────────────────────────────────────
if [[ "$choice" == "1" ]]; then
    subnet_cidr=$(ip -o -f inet addr show 2>/dev/null | awk '!/127.0.0.1/ {print $4}' | head -1)
    if [[ -z "$subnet_cidr" ]]; then
        subnet=$(ip -4 addr show | grep -oP '(?<=inet\s)(?!127)\d+\.\d+\.\d+' | head -1)
        if [[ -z "$subnet" ]]; then
            echo "❌ Could not auto-detect subnet. Please check network interface."
            exit 1
        fi
        subnet_cidr="$subnet.0/24"
    fi
    echo "[*] Scanning subnet: $subnet_cidr"
    log_output "🔍 Local network scan initiated on $subnet_cidr"
    tmpfile=$(mktemp)
    if type register_tmp_file &>/dev/null; then register_tmp_file "$tmpfile"; fi
    scan_output="$OUTPUT_DIR/network_scan_$TIMESTAMP.txt"

    if command -v nmap &>/dev/null; then
        echo "[*] Running fast ping sweep (nmap -sn)..."
        nmap -sn "$subnet_cidr" -oG - 2>/dev/null | awk '/Status: Up/{print $2}' > "$tmpfile"
    else
        echo "[*] Running ICMP ping sweep..."
        subnet_prefix=$(echo "$subnet_cidr" | cut -d/ -f1 | cut -d. -f1-3)
        for i in {1..254}; do
            ip="$subnet_prefix.$i"
            (ping -c 1 -W 1 "$ip" &> /dev/null && echo "$ip" >> "$tmpfile") &
        done
        wait
    fi

    if [[ -s $tmpfile ]]; then
        local up_count
        up_count=$(wc -l < "$tmpfile")
        echo "[+] Hosts up ($up_count detected):"
        cat "$tmpfile" | tee -a "$scan_output"
        echo ""
        echo "Active Nmap Profile: ${CLI_PROFILE} ($CURRENT_PROFILE_FLAGS)"
        echo -e "$(tput setaf 3)⚠️  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
        log_output "✅ Discovered $up_count active hosts. Starting port scans..."
        echo "[*] Starting nmap scans on active hosts..."
        
        while read -r ip; do
            [[ -z "$ip" ]] && continue
            echo "🔎 Scanning $ip ..."
            nmap_output="$OUTPUT_DIR/host_${ip//./_}_$TIMESTAMP.txt"
            nmap $CURRENT_PROFILE_FLAGS "$ip" | tee "$nmap_output"
            log_output "✅ Scan complete for $ip (results: $nmap_output)"
            echo ""
        done < "$tmpfile"
    else
        echo "[*] No active hosts discovered."
        log_output "⚠️ No active hosts discovered in subnet"
    fi
    rm -f "$tmpfile"

elif [[ "$choice" == "2" ]]; then
    target="${CLI_TARGET}"
    if [[ -z "$target" ]]; then
        read -p "Enter the target IP or domain: " target
    fi
    target=$(echo "$target" | sed -E 's|^https?://||; s|/.*$||')
    if [[ -z "$target" ]]; then
        echo "❌ Target cannot be empty"
        exit 1
    fi
    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target" && ! is_valid_domain "$target"; then
            echo "❌ Invalid target format. Must be a valid IP address or domain name."
            log_output "❌ Invalid target provided: $target"
            exit 1
        fi
    fi
    echo -e "$(tput setaf 3)⚠️  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    echo "Active Nmap Profile: ${CLI_PROFILE} ($CURRENT_PROFILE_FLAGS)"
    log_output "🔍 Targeted scan initiated on $target (Profile: $CLI_PROFILE)"
    echo "🔎 Scanning $target ..."
    nmap_output="$OUTPUT_DIR/host_${target//[^a-zA-Z0-9]/_}_$TIMESTAMP.txt"
    nmap $CURRENT_PROFILE_FLAGS "$target" | tee "$nmap_output"
    log_output "✅ Scan complete for $target (results: $nmap_output)"

elif [[ "$choice" == "3" ]]; then
    if [[ -n "$CLI_TARGET" ]]; then
        subdomain_action=1
        target_domain="$CLI_TARGET"
        subdomain_choice=6
    else
        echo "🔍 Subdomain Discovery Workflow:"
        echo "1. Run Subdomain Discovery"
        echo "2. Clean & Deduplicate Results"
        echo "3. View Cleaned Results"
        read -p "Select action [1/2/3]: " subdomain_action
    fi
    
    case $subdomain_action in
        1)
            if [[ -z "${target_domain:-}" ]]; then
                read -p "Enter the target domain (e.g., example.com): " target_domain
            fi
            target_domain=$(echo "$target_domain" | sed -E 's|^https?://||; s|/.*$||')
            
            if [[ -z "$target_domain" ]]; then
                echo "[!] Domain cannot be empty"
                exit 1
            fi
            
            if [[ -z "${subdomain_choice:-}" ]]; then
                echo ""
                echo "🔍 Subdomain Discovery Methods:"
                echo "1. DNS Enumeration"
                echo "2. Common Subdomains (Brute Force)"
                echo "3. Reverse IP Lookup"
                echo "4. Public DNS Records"
                echo "5. Certificate Transparency (crt.sh)"
                echo "6. Aggregated Passive OSINT (crt.sh + HackerTarget + AlienVault + RapidDNS)"
                echo "7. Comprehensive (All Methods)"
                read -p "Select scan type [1/2/3/4/5/6/7]: " subdomain_choice
            fi
            
            case $subdomain_choice in
                1)
                    log_output "🔍 DNS enumeration initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" dns
                    ;;
                2)
                    log_output "🔍 Subdomain brute force initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" common
                    ;;
                3)
                    log_output "🔍 Reverse IP lookup initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" reverse
                    ;;
                4)
                    log_output "🔍 DNS records scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" records
                    ;;
                5)
                    log_output "🔍 Certificate transparency scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" cert
                    ;;
                6)
                    log_output "🔍 Aggregated Passive OSINT scan initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" osint
                    ;;
                7)
                    log_output "🔍 Comprehensive subdomain discovery initiated for $target_domain"
                    bash modules/subdomain_finder.sh "$target_domain" all
                    ;;
                *)
                    echo "[!] Invalid choice"
                    exit 1
                    ;;
            esac
            echo ""
            echo "✅ Subdomain discovery complete!"
            echo "📁 Results saved to: output/subdomains_*/"
            echo ""
            if [[ -z "$CLI_TARGET" ]]; then
                read -p "Would you like to clean the results now? (y/n): " clean_now
                if [[ "$clean_now" =~ ^[Yy]$ ]]; then
                    latest_subdomain_dir=$(ls -dt output/subdomains_*/ 2>/dev/null | head -1)
                    if [[ -n "$latest_subdomain_dir" ]]; then
                        log_output "🧹 Cleaning subdomain results from $latest_subdomain_dir"
                        bash modules/subdomain_cleaner.sh "$latest_subdomain_dir" all
                    fi
                fi
            fi
            ;;
        2)
            echo ""
            echo "📁 Available subdomain discovery results:"
            ls -dt output/subdomains_*/ 2>/dev/null | head -5 || echo "No subdomain results found"
            echo ""
            read -p "Enter full path to subdomain results directory: " subdom_dir
            
            if [[ -d "$subdom_dir" ]]; then
                log_output "🧹 Cleaning subdomain results from $subdom_dir"
                echo ""
                echo "🧹 Cleaning Options:"
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
            echo "📁 Available cleaned results:"
            ls -dt output/clean_subdomains_*/ 2>/dev/null | head -5 || echo "No cleaned results found"
            echo ""
            read -p "Enter cleaned results directory (or press Enter to skip): " clean_dir
            if [[ -n "$clean_dir" && -d "$clean_dir" ]]; then
                echo ""
                echo "📋 Cleaned Results Files:"
                ls -lh "$clean_dir" | tail -n +2 | awk '{print $9, "(" $5 ")"}'
            fi
            ;;
        *)
            echo "[!] Invalid action"
            exit 1
            ;;
    esac

elif [[ "$choice" == "4" ]]; then
    target_url="${CLI_TARGET}"
    if [[ -z "$target_url" ]]; then
        read -p "Enter the target URL (e.g., http://target.com): " target_url
    fi
    if [[ -n "$target_url" && ! "$target_url" =~ ^https?:// ]]; then
        target_url="http://$target_url"
    fi

    if [[ -z "$target_url" ]]; then
        echo "[!] URL cannot be empty"
        exit 1
    fi

    echo ""
    echo -e "$(tput setaf 3)⚠️  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    log_output "🔍 Web vulnerability scan initiated for $target_url"

    bash modules/web_vulnerabilities.sh "$target_url" 10

    echo ""
    echo "✅ Web vulnerability scan complete!"
    echo "📁 Results saved to: output/web_vulns_*/"
    log_output "✅ Web vulnerability scan complete for $target_url"

elif [[ "$choice" == "5" ]]; then
    target_file="${CLI_TARGET}"
    if [[ -z "$target_file" ]]; then
        read -p "Enter path to target file (default: targets.txt): " target_file
        target_file=${target_file:-targets.txt}
    fi

    if [[ ! -f "$target_file" ]]; then
        echo "❌ File '$target_file' not found."
        echo "💡 Tip: Create a file with one IP/domain per line (e.g., echo 'example.com' > targets.txt)"
        exit 1
    fi

    if [[ -n "$CLI_TARGET" ]]; then
        mode="recon"
        max_workers=5
    else
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
    fi

    log_output "🚀 Initiating Multi-Target Batch Scan from $target_file (Mode: $mode, Workers: $max_workers)"
    bash modules/batch_runner.sh "$target_file" "$mode" "$max_workers"
    log_output "✅ Multi-Target Batch Scan completed for $target_file"

elif [[ "$choice" == "6" ]]; then
    target_whois="${CLI_TARGET}"
    if [[ -z "$target_whois" ]]; then
        read -p "Enter target domain or IP (e.g., example.com or 8.8.8.8): " target_whois
    fi
    target_whois=$(echo "$target_whois" | sed -E 's|^https?://||; s|/.*$||')

    if [[ -z "$target_whois" ]]; then
        echo "[!] Target cannot be empty"
        exit 1
    fi

    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target_whois" && ! is_valid_domain "$target_whois"; then
            echo "❌ Invalid target format. Must be a valid IP address or domain name."
            exit 1
        fi
    fi

    if [[ -n "$CLI_TARGET" ]]; then
        mode="all"
    else
        echo ""
        echo "🔍 WHOIS & Reverse Lookup Options:"
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
    fi

    echo ""
    echo -e "$(tput setaf 3)⚠️  Press CTRL+C at any time to cancel the scan.$(tput sgr0)"
    log_output "🔍 WHOIS & Reverse Lookup recon initiated for $target_whois (mode: $mode)"
    bash modules/whois_recon.sh "$target_whois" "$mode"

    echo ""
    echo "✅ WHOIS & Reverse Lookup recon complete!"
    echo "📁 Results saved to: output/whois_*/"
    log_output "✅ WHOIS & Reverse Lookup recon complete for $target_whois"

elif [[ "$choice" == "7" ]]; then
    target_passive="${CLI_TARGET}"
    if [[ -z "$target_passive" ]]; then
        read -p "Enter target domain or IP for passive OSINT (e.g., example.com): " target_passive
    fi
    target_passive=$(echo "$target_passive" | sed -E 's|^https?://||; s|/.*$||')

    if [[ -z "$target_passive" ]]; then
        echo "[!] Target cannot be empty"
        exit 1
    fi

    if type is_valid_ip &>/dev/null && type is_valid_domain &>/dev/null; then
        if ! is_valid_ip "$target_passive" && ! is_valid_domain "$target_passive"; then
            echo "❌ Invalid target format. Must be a valid IP address or domain name."
            exit 1
        fi
    fi

    echo ""
    echo -e "$(tput setaf 3)⚠️  Passive OSINT queries may take a few seconds.$(tput sgr0)"
    log_output "🔍 Passive OSINT scan initiated for $target_passive"
    bash modules/passive.sh "$target_passive"

    echo ""
    echo "✅ Passive OSINT completed!"
    echo "📁 Results saved to: output/passive_${target_passive//[^a-zA-Z0-9.-]/_}_*.json"
    log_output "✅ Passive OSINT scan complete for $target_passive"

elif [[ "$choice" == "8" ]]; then
    echo "📁 Recent Scan Results:"
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
    echo "📊 Generating Report..."
    report_file="$OUTPUT_DIR/report_$TIMESTAMP.txt"
    {
        echo "═════════════════════════════════════════════════════════"
        echo "ALL-RECON - SCAN REPORT"
        echo "Generated: $(date)"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        echo "📁 Scans Available:"
        ls -1 "$OUTPUT_DIR"/*.txt 2>/dev/null | grep -v report || echo "No scans found"
        echo ""
        echo "Session Log: $SESSION_LOG"
        echo ""
        echo "═════════════════════════════════════════════════════════"
    } | tee "$report_file"
    echo ""
    echo "✅ Report saved to: $report_file"
    log_output "📊 Report generated: $report_file"

elif [[ "$choice" == "10" ]]; then
    echo -e "$(tput bold)[*] Exiting ALL-RECON Recon Engine. Stay unseen. 🛡️$(tput sgr0)"
    log_output "🛑 Session ended"
    exit 0

else
    echo -e "$(tput bold)[!] Invalid choice. Exiting.$(tput sgr0)"
    exit 1
fi

echo "[*] Scan complete."
log_output "🏁 Workflow step complete. Results in $OUTPUT_DIR/"
echo ""
echo "📁 All results saved to: $OUTPUT_DIR/"
echo "📋 Session log: $SESSION_LOG"
