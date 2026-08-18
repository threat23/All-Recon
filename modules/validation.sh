#!/bin/bash

# ===================================================================
# ALL-RECON - INPUT VALIDATION & SAFETY UTILITIES
# Module for validating IPs, domains, URLs, paths, and signal safety
# ===================================================================

# Validate IPv4 address
is_valid_ip() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        return 1
    fi
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ $ip =~ $rx ]]; then
        local IFS='.'
        local -a octets=($ip)
        [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
        return $?
    else
        return 1
    fi
}

# Validate Domain Name (FQDN)
is_valid_domain() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        return 1
    fi
    # Pattern for standard domain names
    local rx='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    if [[ $domain =~ $rx ]]; then
        return 0
    else
        return 1
    fi
}

# Validate URL (http/https)
is_valid_url() {
    local url="$1"
    if [[ -z "$url" ]]; then
        return 1
    fi
    local rx='^https?://([a-zA-Z0-9.-]+|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]+)?(/.*)?$'
    if [[ $url =~ $rx ]]; then
        return 0
    else
        return 1
    fi
}

# Validate integer range
is_valid_number() {
    local val="$1"
    local min="${2:-1}"
    local max="${3:-999999}"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then
        return 0
    fi
    return 1
}

# Sanitize path to prevent directory traversal
sanitize_path() {
    local user_path="$1"
    # Remove leading dots or slashes attempting traversal
    local clean_path
    clean_path=$(echo "$user_path" | sed -E 's/\.\.\///g' | sed -E 's/^\/+//g')
    echo "$clean_path"
}

# Global list of temporary files to clean up on exit/signal
declare -g -a ALL_RECON_TMP_FILES=()

register_tmp_file() {
    ALL_RECON_TMP_FILES+=("$1")
}

cleanup_tmp_files() {
    for f in "${ALL_RECON_TMP_FILES[@]}"; do
        if [[ -n "$f" && -e "$f" ]]; then
            rm -rf "$f" 2>/dev/null
        fi
    done
    ALL_RECON_TMP_FILES=()
}

# Standard signal handler trap
setup_signal_traps() {
    trap 'cleanup_tmp_files; echo -e "\n\n[WARN] Scan interrupted by user or signal. Cleaning up..."; exit 130' SIGINT SIGTERM
    trap 'cleanup_tmp_files' EXIT
}
