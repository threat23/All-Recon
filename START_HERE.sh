#!/bin/bash

# ===================================================================
# ALL-RECON - START HERE
# First-time user guide
# ===================================================================

echo ""
echo "+================================================================+"
echo "|                                                                |"
echo "|         [TARGET] ALL-RECON - PENTESTER AUTOMATION SUITE [TARGET]         |"
echo "|                                                                |"
echo "|  Automate the boring. Focus on the interesting.              |"
echo "|  Smooth workflow. Uninterrupted focus. Get stuff done.        |"
echo "|                                                                |"
echo "+================================================================+"
echo ""

echo "[LIST] PROJECT STRUCTURE"
echo "-------------------------------------------------------------------"
echo ""
echo "[FILE] Documentation (START HERE):"
echo "   1. README.md                - Full project guide"
echo "   2. WORKFLOW_GUIDE.md        - Practical workflow patterns"
echo "   3. PROJECT_MANIFEST.md      - Complete project overview"
echo ""
echo "-> Getting Started:"
echo "   1. install.sh               - Setup & install dependencies"
echo "   2. QUICKSTART.sh            - 5-minute quick start"
echo "   3. all_recon.sh      - Main automation tool"
echo ""
echo "[CONFIG]  Customization:"
echo "   - config/nmap_profiles.conf       - Scan templates"
echo "   - config/automation_rules.conf    - Behavior settings"
echo ""
echo "[SETUP] Extended Features:"
echo "   - modules/recon.sh               - Reconnaissance module"
echo "   - modules/reporting.sh           - Report generation"
echo ""
echo "-------------------------------------------------------------------"
echo ""

echo "[TARGET] FIRST-TIME SETUP (Choose one):"
echo ""
echo "Option A: Full Setup (Recommended)"
echo "   bash install.sh"
echo "   -> Installs dependencies"
echo "   -> Creates directory structure"
echo "   -> Validates everything"
echo ""
echo "Option B: Quick Setup"
echo "   bash QUICKSTART.sh"
echo "   -> Quick checks"
echo "   -> Creates directories"
echo "   -> Gets you running fast"
echo ""
echo "Option C: Manual (You know what you're doing)"
echo "   ./all_recon.sh"
echo "   -> Run main tool directly"
echo "   -> (May fail if dependencies missing)"
echo ""

echo "-------------------------------------------------------------------"
echo ""

echo "[DOCS] LEARNING PATH:"
echo ""
echo "New User?"
echo "   1. bash install.sh"
echo "   2. read README.md"
echo "   3. ./all_recon.sh"
echo "   4. Explore config/ and modules/"
echo ""
echo "Want Practical Examples?"
echo "   1. cat WORKFLOW_GUIDE.md"
echo "   2. See real-world scenarios"
echo "   3. Follow the patterns"
echo ""
echo "Want Full Technical Details?"
echo "   1. cat PROJECT_MANIFEST.md"
echo "   2. Review configuration files"
echo "   3. Check modules/ directory"
echo ""

echo "-------------------------------------------------------------------"
echo ""

echo "[FAST] QUICK COMMANDS:"
echo ""
echo "Setup:"
echo "   chmod +x *.sh modules/*.sh      # Make scripts executable"
echo "   bash install.sh                 # Install dependencies"
echo ""
echo "Usage:"
echo "   ./all_recon.sh           # Run main tool"
echo "   ./modules/recon.sh <target> all # DNS/WHOIS recon"
echo "   ./modules/reporting.sh output/  # Generate report"
echo ""
echo "Check Results:"
echo "   ls -lh output/                  # View scan results"
echo "   cat logs/session_*.log          # View session logs"
echo "   ls -lh output/reports/          # View reports"
echo ""

echo "-------------------------------------------------------------------"
echo ""

read -p "Ready to get started? Would you like to run setup now? (y/n): " response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Choose setup type:"
    echo "  1) Full Setup (install.sh) - Recommended"
    echo "  2) Quick Setup (QUICKSTART.sh)"
    echo "  3) Skip - I'll do it manually"
    echo ""
    read -p "Enter choice [1/2/3]: " choice
    
    case $choice in
        1)
            echo ""
            bash install.sh
            ;;
        2)
            echo ""
            bash QUICKSTART.sh
            ;;
        3)
            echo "No problem! Run 'bash install.sh' when you're ready."
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
else
    echo ""
    echo "[OK] Setup files are ready when you are!"
    echo "Run 'bash install.sh' to get started."
fi

echo ""
echo "==================================================================="
echo ""
echo "[NEXT] Next Steps:"
echo "  1. Run: bash install.sh"
echo "  2. Read: README.md"
echo "  3. Try: ./all_recon.sh"
echo ""
echo "[TIP] Remember:"
echo "  ALL-RECON is about smooth workflow."
echo "  Set it up once, run it many times."
echo "  Let automation handle the routine."
echo "  You focus on the interesting stuff."
echo ""
echo "==================================================================="
echo ""
