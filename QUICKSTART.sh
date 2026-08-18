#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - QUICK START GUIDE
# Get up and running in 60 seconds
# ═══════════════════════════════════════════════════════════════════

echo "-> ALL-RECON Quick Start"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check dependencies
echo "[LIST] Checking dependencies..."
deps=("nmap" "toilet" "lolcat" "curl" "dig")

missing_deps=()
for dep in "${deps[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        missing_deps+=("$dep")
    else
        echo "   [OK] $dep"
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo ""
    echo "[WARN]  Missing dependencies: ${missing_deps[@]}"
    echo ""
    echo "Install with:"
    echo "  sudo apt update"
    echo "  sudo apt install nmap toilet curl dnsutils -y"
    echo "  sudo gem install lolcat"
    echo ""
fi

echo ""
echo "[DIR] Creating project structure..."
mkdir -p output logs config/templates modules

echo "   [OK] output/"
echo "   [OK] logs/"
echo "   [OK] config/"
echo "   [OK] modules/"

echo ""
echo "[SECURITY] Setting permissions..."
chmod +x ./*.sh modules/*.sh 2>/dev/null

echo "   [OK] Scripts executable"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "[READY] Ready to go!"
echo ""
echo "Next steps:"
echo "  1. Run: ./all_recon.sh"
echo "  2. Select scan type (1 or 2)"
echo "  3. Automation handles the rest!"
echo ""
echo "[TIP] Pro tips:"
echo "  - View last results: Option 3"
echo "  - Generate report: Option 4"
echo "  - Check 'output/' folder for organized results"
echo "  - Customize profiles: config/nmap_profiles.conf"
echo ""
echo "[DOCS] Documentation:"
echo "  - Read README.md for full guide"
echo "  - See modules/ for extended features"
echo ""
