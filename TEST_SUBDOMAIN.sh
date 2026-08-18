#!/bin/bash

# ALL-RECON - SUBDOMAIN DISCOVERY TEST GUIDE

echo ""
echo "+================================================================+"
echo "|  [SCAN] SUBDOMAIN DISCOVERY - TEST GUIDE                           |"
echo "+================================================================+"
echo ""

echo "[LIST] QUICK TEST OPTIONS"
echo "==================================================================="
echo ""

echo "Option 1: Test via Main Menu (Interactive)"
echo "-----------------------------------------------------------------"
echo "$ ./all_recon.sh"
echo "Select: 3 (Subdomain Discovery)"
echo "Enter domain: example.com"
echo "Select scan type: 6 (Comprehensive)"
echo ""
echo "[OK] This will run ALL discovery methods on example.com"
echo ""

echo "Option 2: Test Individual Methods (Direct)"
echo "-----------------------------------------------------------------"
echo ""

echo "Test 1: DNS Enumeration"
echo "  $ ./modules/subdomain_finder.sh example.com dns"
echo ""

echo "Test 2: Common Subdomains Brute Force"
echo "  $ ./modules/subdomain_finder.sh example.com common"
echo ""

echo "Test 3: Reverse IP Lookup"
echo "  $ ./modules/subdomain_finder.sh example.com reverse"
echo ""

echo "Test 4: Public DNS Records"
echo "  $ ./modules/subdomain_finder.sh example.com records"
echo ""

echo "Test 5: Certificate Transparency"
echo "  $ ./modules/subdomain_finder.sh example.com cert"
echo ""

echo "Test 6: Comprehensive (All Methods)"
echo "  $ ./modules/subdomain_finder.sh example.com all"
echo ""

echo "Option 3: Quick Syntax Check (No Live Requests)"
echo "-----------------------------------------------------------------"
echo "$ bash -n modules/subdomain_finder.sh"
echo "$ ./all_recon.sh"
echo ""

echo "==================================================================="
echo ""

echo "[REPORT] WHAT TO EXPECT"
echo "==================================================================="
echo ""

echo "Results will be saved to:"
echo "  [DIR] output/subdomains_YYYYMMDD_HHMMSS/"
echo ""

echo "Files generated:"
echo "  - dns_enum_TIMESTAMP.txt          - DNS zone transfers & records"
echo "  - common_subdomains_TIMESTAMP.txt - Discovered common subdomains"
echo "  - reverse_ip_TIMESTAMP.txt        - Reverse DNS results"
echo "  - dns_records_TIMESTAMP.txt       - All DNS record types"
echo "  - cert_transparency_TIMESTAMP.txt - SSL certificate findings"
echo "  - summary_TIMESTAMP.txt           - Scan summary"
echo ""

echo "Logs saved to:"
echo "  [LIST] logs/subdomain_YYYYMMDD_HHMMSS.log"
echo ""

echo "==================================================================="
echo ""

echo "[TARGET] RECOMMENDED FIRST TEST"
echo "-----------------------------------------------------------------"
echo ""
echo "1. Start main tool:"
echo "   ./all_recon.sh"
echo ""
echo "2. Select option 3 (Subdomain Discovery)"
echo ""
echo "3. Enter domain: example.com"
echo ""
echo "4. Select option 6 (Comprehensive)"
echo ""
echo "5. Wait for results (~2-3 minutes)"
echo ""
echo "6. Review results:"
echo "   ls -lh output/subdomains_*"
echo "   cat output/subdomains_*/summary*.txt"
echo ""

echo "==================================================================="
echo ""

echo "[READY] TIPS"
echo "-----------------------------------------------------------------"
echo ""
echo "- Use with AUTHORIZED domains only"
echo "- Common method finds: www, mail, ftp, admin, dev, staging, etc."
echo "- Cert transparency shows what was publicly logged"
echo "- Reverse IP can reveal other domains on same server"
echo "- DNS records show infrastructure details (MX, NS, TXT)"
echo ""

echo "==================================================================="
echo ""

read -p "Ready to test? Run: ./all_recon.sh [Enter]"
