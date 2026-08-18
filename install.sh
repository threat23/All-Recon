#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - INSTALLATION & SETUP
# Fully automated environment setup
# ═══════════════════════════════════════════════════════════════════

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ALL-RECON - PENTESTER AUTOMATION SUITE                       ║"
echo "║  Installation & Setup                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "[OK] Detected: Linux"
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "[OK] Detected: macOS"
    OS="macos"
else
    echo "[ERROR] Unsupported OS: $OSTYPE"
    exit 1
fi

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Step 1: Checking & Installing Dependencies"
echo "─────────────────────────────────────────────────────────────────"
echo ""

install_deps() {
    if [[ "$OS" == "linux" ]]; then
        echo "[SETUP] Installing dependencies (Ubuntu/Debian)..."
        echo "   Note: You may be prompted for your password"
        echo ""
        
        sudo apt update -qq
        
        deps=("nmap" "curl" "dnsutils" "toilet" "python3" "python3-pip")
        for dep in "${deps[@]}"; do
            if ! dpkg -l | grep -q "^ii  $dep"; then
                echo "   [INSTALL] Installing $dep..."
                sudo apt install "$dep" -y -qq
            else
                echo "   [OK] $dep already installed"
            fi
        done

        if [[ -f "requirements.txt" ]]; then
            echo "   [INSTALL] Installing Python dependencies from requirements.txt..."
            python3 -m pip install --break-system-packages -r requirements.txt 2>/dev/null || pip3 install -r requirements.txt
        fi
        
        # Install lolcat via gem (may not be available in apt)
        if ! command -v lolcat &> /dev/null; then
            echo "   [INSTALL] Installing lolcat (Ruby gem)..."
            if command -v gem &> /dev/null; then
                sudo gem install lolcat -q 2>/dev/null || echo "   [WARN]  gem not available, trying apt..."
                sudo apt install lolcat -y -qq 2>/dev/null || echo "   [WARN]  lolcat not available via apt"
            fi
        else
            echo "   [OK] lolcat already installed"
        fi
        
    elif [[ "$OS" == "macos" ]]; then
        echo "[SETUP] Installing dependencies (macOS with Homebrew)..."
        
        if ! command -v brew &> /dev/null; then
            echo "[ERROR] Homebrew not found. Install from: https://brew.sh"
            exit 1
        fi
        
        deps=("nmap" "curl" "bind" "figlet" "python3")
        for dep in "${deps[@]}"; do
            if brew list "$dep" &>/dev/null 2>&1; then
                echo "   [OK] $dep already installed"
            else
                echo "   [INSTALL] Installing $dep..."
                brew install "$dep" -q
            fi
        done

        if [[ -f "requirements.txt" ]]; then
            echo "   [INSTALL] Installing Python dependencies from requirements.txt..."
            python3 -m pip install -r requirements.txt 2>/dev/null || pip3 install -r requirements.txt
        fi

        if ! command -v lolcat &> /dev/null; then
            echo "   [INSTALL] Installing lolcat..."
            brew install lolcat -q || gem install lolcat -q
        else
            echo "   [OK] lolcat already installed"
        fi
    fi
}

install_deps

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Step 2: Setting Up Project Structure"
echo "─────────────────────────────────────────────────────────────────"
echo ""

create_structure() {
    dirs=("output" "logs" "config" "modules" "config/templates")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            echo "   [DIR] Created: $dir/"
        else
            echo "   [OK] $dir/ exists"
        fi
    done
}

create_structure

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Step 3: Setting Permissions"
echo "─────────────────────────────────────────────────────────────────"
echo ""

chmod +x ./*.sh modules/*.sh 2>/dev/null || true
echo "   [OK] Scripts are executable"

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Step 4: Verifying Installation"
echo "─────────────────────────────────────────────────────────────────"
echo ""

verify_setup() {
    tools=("nmap" "curl" "dig" "toilet" "python3")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            version=$(command -v "$tool" 2>&1)
            echo "   [OK] $tool available"
        else
            echo "   [ERROR] $tool NOT FOUND"
        fi
    done

    if python3 -m pip --version &> /dev/null; then
        echo "   [OK] pip available"
    else
        echo "   [ERROR] pip NOT FOUND"
    fi
    
    if [[ -f "all_recon.sh" ]]; then
        echo "   [OK] Main script ready"
    else
        echo "   [ERROR] Main script not found"
    fi
}

verify_setup

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  [READY] SETUP COMPLETE                                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "[TARGET] Next Steps:"
echo ""
echo "   1. Run the main tool:"
echo "      ./all_recon.sh"
echo ""
echo "   2. Or run quick start guide:"
echo "      bash QUICKSTART.sh"
echo ""
echo "   3. Read full documentation:"
echo "      cat README.md"
echo ""
echo "[LIST] Project structure:"
echo "   - all_recon.sh    - Main automation engine"
echo "   - config/                - Configuration files"
echo "   - modules/               - Extended functionality"
echo "   - output/                - Scan results (auto-organized)"
echo "   - logs/                  - Session logs"
echo ""
echo "[TIP] Pro tip: Customize config/nmap_profiles.conf for your workflow"
echo ""
