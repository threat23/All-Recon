#!/bin/bash
#!/bin/bash

# ─── GLORIOUS BANNER ────────────────────────────────────────
clear

# Dependency checks
for cmd in toilet lolcat; do
    command -v $cmd &>/dev/null || {
        echo "[ERROR] $cmd is not installed. Install it first."
        [[ $cmd == "lolcat" ]] && echo "    sudo gem install lolcat"
        [[ $cmd == "toilet" ]] && echo "    sudo apt install toilet"
        exit 1
    }
done

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

# ─── CHECK DEPENDENCIES ───────────────────────────────
command -v figlet &>/dev/null || { echo "figlet missing. Run: sudo apt install figlet"; exit 1; }
command -v nmap &>/dev/null || { echo "nmap missing. Run: sudo apt install nmap"; exit 1; }

# ─── DISPLAY BANNER ───────────────────────────────────
figlet -w 120 "ALL-RECON" | lolcat 2>/dev/null || figlet -w 120 "ALL-RECON"
echo ""

# ─── IP DETECTION ──────────────────────────────────────────────

# Detect internal IP (first usable IP)
internal_ip=$(hostname -I | awk '{print $1}')

# Detect public IP (from web)
external_ip=$(curl -s ifconfig.me)

# Fallback if curl fails
if [[ -z "$external_ip" ]]; then
    external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
fi

# Show them to user
echo ""
echo -e "$(tput bold)[IP] Internal IP  : $internal_ip$(tput sgr0)"
echo -e "$(tput bold)[IP] External IP  : $external_ip$(tput sgr0)"
echo ""

# ─── MENU ─────────────────────────────────────────────
echo "Select Scan Type:"
echo "1. Local Network Scan (Ping Sweep + Port Scan)"
echo "2. Scan Specific Host (Website IP or Domain)"
echo "3. Exit / Cancel"
read -p "Enter choice [1/2/3]: " choice
echo ""

# ─── SCAN OPTIONS ─────────────────────────────────────
if [[ "$choice" == "1" ]]; then
    # ─── OPTION 1: LOCAL NETWORK SCAN ─────────────────────
    subnet=$(ip -4 addr show | grep -oP '(?<=inet\s)(?!127)\d+\.\d+\.\d+')
    echo "[*] Scanning subnet: $subnet.0/24"
    tmpfile=$(mktemp)

    for i in {1..254}; do
        ip="$subnet.$i"
        (ping -c 1 -W 1 $ip &> /dev/null && echo "$ip" >> "$tmpfile") &
    done
    wait

    if [[ -s $tmpfile ]]; then
        echo "[+] Hosts up:"
        cat "$tmpfile"
        echo ""
        echo "[*] Starting full nmap scans..."

        while read ip; do
            echo "[SCAN] Scanning $ip ..."
            nmap -sS -O --osscan-guess --osscan-limit --max-os-tries 1 -T4 -Pn -p- $ip | tee "scan_$ip.txt"
            echo ""
        done < "$tmpfile"
    else
        echo "[*] No Host was up. Contact [+] ALL-RECON or THREAT [+]"
    fi

    rm -f "$tmpfile"

elif [[ "$choice" == "2" ]]; then
    # ─── OPTION 2: REMOTE TARGET SCAN ─────────────────────
    read -p "Enter the target IP or domain: " target
    echo "[SCAN] Scanning $target ..."
    nmap -sS -O --osscan-guess --osscan-limit --max-os-tries 1 -T4 -Pn -p- $target | tee "scan_${target//[^a-zA-Z0-9]/_}.txt"

elif [[ "$choice" == "3" ]]; then
    # ─── OPTION 3: EXIT ───────────────────────────────────
    echo -e "$(tput bold)[*] Exiting ALL-RECON Recon Engine. Stay unseen. [SAFE]$(tput sgr0)"
    exit 0

else
    # ─── INVALID INPUT ────────────────────────────────────
    echo -e "$(tput bold)[!] Invalid choice. Exiting.$(tput sgr0)"
    exit 1
fi

echo "[*] Scan complete."
