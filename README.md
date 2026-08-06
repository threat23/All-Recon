# ALL-RECON - Pentester Workflow Automation Suite

> *"As a pentester, I have a good day when my workflow is smooth and uninterrupted. Pushing routine tasks to the background (sweet automation!) helps me stay focused. It frees up my mind to work on interesting findings and attack sequences that not everyone can see. Plus, it feels good to be productive and get stuff done."*

---

## Mission Statement

**ALL-RECON** is a streamlined automation suite designed for penetration testers who demand efficiency. It eliminates routine, repetitive scanning and reconnaissance tasks—freeing your mental bandwidth to focus on **the interesting stuff**: vulnerability chains, creative exploitation techniques, and insights that matter.

### Core Philosophy

- **Automate the Boring** → Routine scans, data collection, report generation—all hands-off
- **Focus on the Interesting** → Deep analysis, attack sequences, novel findings
- **Smooth Workflow** → Minimal friction. Minimal interruptions. Maximum productivity
- **Get Stuff Done** → Quick wins. Fast turnaround. Observable results

---

## Features

✅ **Local Network Reconnaissance** - Automated ping sweep + comprehensive port scanning  
✅ **Targeted Host Analysis** - Deep-dive scanning for specific IPs/domains  
✅ **Subdomain Discovery** - Comprehensive subdomain enumeration & DNS analysis  
✅ **Subdomain Cleaning** - Remove duplicates, deduplicate, organize & export results  
✅ **IP Detection** - Automatic internal & external IP discovery  
✅ **Dependency Management** - Smart pre-flight checks for required tools  
✅ **Beautiful Output** - ASCII art + colored logging for quick visual parsing  
✅ **Modular Architecture** - Easy to extend with custom recon modules  
✅ **Automated Reporting** - Scan results captured for later analysis  
✅ **Background Processing** - Parallel scanning to maximize throughput  

---

## Installation

### Prerequisites

```bash
sudo apt update
sudo apt install nmap toilet git curl dnsutils -y
sudo gem install lolcat  # or: sudo apt install lolcat
```

### Quick Start

```bash
cd /home/threat23/Desktop/Project
chmod +x all_recon.sh
./all_recon.sh
```

---

## Usage

### 1. Local Network Scan
Discovers all active hosts on your network and performs aggressive nmap scans:
```bash
./all_recon.sh
# Select option: 1
```

### 2. Specific Host Analysis
Deep reconnaissance on a single target:
```bash
./all_recon.sh
# Select option: 2
# Enter target IP or domain
```

### 3. Subdomain Discovery & Enumeration
Comprehensive subdomain reconnaissance using multiple methods:
```bash
./all_recon.sh
# Select option: 3
# Choose from: DNS, Brute Force, Reverse IP, DNS Records, Cert Transparency, or All
```

**Subdomain Discovery Methods:**
- DNS zone transfer attempts
- Common subdomain brute force (60+ wordlist)
- Reverse IP lookup
- Public DNS records scan (A, AAAA, MX, NS, TXT, SPF, etc.)
- SSL/TLS certificate transparency logs

**After Discovery - Automatic Cleaning:**
```
Option: Clean results (Y/N)
→ Removes duplicates
→ Resolves IP addresses
→ Filters invalid entries
→ Organizes by IP
→ Exports CSV/JSON
```

**Or Clean Manually:**
```bash
./all_recon.sh
# Select option: 3
# Option: 2 (Clean & Deduplicate Results)
# Choose cleaning action (extract, deduplicate, active, group, csv, json, all)
```

**Direct Module Usage:**
```bash
./modules/subdomain_finder.sh example.com all
./modules/subdomain_cleaner.sh output/subdomains_*/ all
```

### 4. View Results & Generate Reports
```bash
./all_recon.sh
# Select option: 4 (View Last Results)
# Select option: 5 (Generate Report)
```

---

## Project Structure

```
Project/
├── all_recon.sh         # Main automation engine
├── all_recon_alt.sh               # Alternative workflow variant
├── config/
│   ├── nmap_profiles.conf      # Pre-tuned scan profiles
│   └── automation_rules.conf   # Custom automation settings
├── modules/
│   ├── recon.sh                # Reconnaissance module
│   ├── exploits.sh             # Exploitation tracking
│   └── reporting.sh            # Report generation
├── output/                      # Auto-generated scan results
└── README.md                    # This file
```

---

## Workflow Philosophy

### Before ALL-RECON
❌ Open terminal → Run manual nmap → Wait for results → Parse output → Switch context → Repeat 50 times  
❌ Mental energy wasted on routine tasks  
❌ Disorganized results scattered across terminal  
❌ Slow iteration cycle

### With ALL-RECON
✅ Run once → Everything runs in parallel → Results auto-captured → Focus on analysis  
✅ Mental energy reserved for interesting findings  
✅ Organized, structured output ready for deep-dive  
✅ Fast iteration cycle—test hypotheses, spot patterns

---

## Automation in Action

| Task | Manual | ALL-RECON |
|------|--------|-----------|
| Subnet scan | 5-10 min | ~2 min (parallel) |
| 254 host ping sweep | Manual loop | Automated parallel |
| Port scanning all hosts | Sequential (hours) | Parallel (minutes) |
| Result parsing | Tedious grep | Auto-captured & timestamped |
| Next target setup | Copy-paste | Instant |

---

## Key Benefits for Your Workflow

1. **Uninterrupted Focus** - Start scan → automation handles it → you analyze findings
2. **Smooth Workflow** - No context switching. No manual command repetition
3. **Mind Stays Sharp** - Energy preserved for the interesting attack sequences
4. **Productivity Boost** - Measurable results. Visible progress. Momentum
5. **Professional Output** - Timestamped, organized, report-ready results

---

## Configuration

### Customize Scan Profiles

Edit `config/nmap_profiles.conf` to define your standard scan templates:

```bash
# Fast reconnaissance
PROFILE_FAST="-T4 -p- --top-ports 100"

# Thorough analysis
PROFILE_THOROUGH="-sS -O --osscan-guess -T3 -A -p-"

# Stealth mode
PROFILE_STEALTH="-T1 -p- -sS"
```

### Automation Rules

Edit `config/automation_rules.conf` to define which actions trigger automatically:

```bash
# Auto-export results
AUTO_EXPORT_FORMAT="xml,txt,json"

# Auto-notify on high-risk ports detected
ALERT_ON_PORTS="22,3389,5985,5986"

# Parallel scan limit
MAX_PARALLEL_SCANS=4
```

---

## Output & Results

All scan results are automatically saved with timestamps:

```
output/
├── scan_192.168.1.100_20260609_143022.txt
├── scan_192.168.1.101_20260609_143022.txt
└── scan_results_summary_20260609.txt
```

---

## Web Vulnerability Testing

After reconnaissance identifies targets, vulnerability testing uncovers exploitable issues. Comprehensive guide included:

📖 **[WEB_VULNERABILITIES.md](./WEB_VULNERABILITIES.md)** — Complete reference for:
- **SQL Injection (SQLi)** - Detection methods, payloads, automated testing
- **Cross-Site Scripting (XSS)** - Stored, reflected, DOM-based + bypass techniques
- **OS Command Injection** - Shell metacharacters, data exfiltration, reverse shells
- **CSRF** - Token validation, PoC generation
- **Authentication & Authorization** - Weak credentials, session issues, escalation
- **Broken Access Control** - IDOR, privilege escalation, path traversal
- **Sensitive Data Exposure** - SSL/TLS verification, data at rest, exposed endpoints
- **XXE & BOLA** - XML attacks, object-level authorization bypass

Quick reference with:
✅ Testing payloads for each vulnerability class  
✅ Automated tool integration (SQLMap, Commix, OWASP ZAP, Burp)  
✅ Detection workflows and remediation indicators  
✅ OWASP Top 10 reference matrix

---

## Advanced Usage

### Batch Multiple Targets

```bash
echo "192.168.1.1
192.168.1.5
10.0.0.50" | while read target; do
  ./all_recon.sh
done
```

### Parse Results for Vulnerability Signals

```bash
grep -E "open|filtered" output/*.txt | grep -E "22|445|3389|5985"
```

### Generate Quick Report

```bash
./modules/reporting.sh output/
```

---

## Performance Tips

- Run during off-peak hours for stealth
- Use `-T4` (Aggressive) for fast networks
- Use `-T1` (Paranoid) for evasion requirements
- Increase `MAX_PARALLEL_SCANS` for larger subnets (⚠️ may trigger IDS)
- Combine with proxies/VPN for anonymous reconnaissance

---

## Troubleshooting

### "lolcat is not installed"
```bash
sudo gem install lolcat
# or
sudo apt install lolcat
```

### "nmap: command not found"
```bash
sudo apt install nmap
```

### Permission Denied
```bash
chmod +x all_recon.sh all_recon_alt.sh
```

### Slow Network Scans
- Check your network bandwidth
- Reduce parallel processes in `config/automation_rules.conf`
- Use faster scan templates (`-T4` or higher)

---

## Ethical Use & Legal Notice

This toolkit is designed for **authorized security testing only**. Unauthorized access to computer systems is illegal. Always obtain written permission before conducting security assessments.

---

## Credits

**Created by:** Humphrey Chile | THREAT | ALL-RECON | & JOSH  
**Division:** Code Red Ops | Threat Intelligence Division  
**Philosophy:** Scan Deep. Strike Hard. Vanish Clean.

---

## License

Internal Use Only | Security Professionals

---

**Remember:** The best pentester is a productive pentester. Automation is not laziness—it's **professional efficiency**.

*Your perimeter just became my playground.* 🎯
