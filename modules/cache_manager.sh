#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - CACHE MANAGER MODULE
# Implements result caching to avoid redundant scans
# Philosophy: Don't rescan what you already know
# ═══════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="output/cache"
CACHE_TTL=86400  # 24 hours default TTL
CACHE_INDEX="$CACHE_DIR/cache_index.db"

mkdir -p "$CACHE_DIR"

# Initialize cache index
init_cache() {
    if [[ ! -f "$CACHE_INDEX" ]]; then
        echo "# ALL-RECON Cache Index" > "$CACHE_INDEX"
        echo "# Format: target|scan_type|timestamp|cache_file" >> "$CACHE_INDEX"
    fi
}

# Generate cache key
generate_cache_key() {
    local target="$1"
    local scan_type="$2"
    local scan_params="${3:-default}"
    echo "$target|$scan_type|$scan_params" | md5sum | cut -d' ' -f1
}

# Check if cached result exists and is valid
check_cache() {
    local target="$1"
    local scan_type="$2"
    local scan_params="${3:-default}"
    local ttl="${4:-$CACHE_TTL}"

    init_cache

    local cache_key=$(generate_cache_key "$target" "$scan_type" "$scan_params")
    local cache_entry=$(grep "^$cache_key" "$CACHE_INDEX" 2>/dev/null)

    if [[ -z "$cache_entry" ]]; then
        return 1  # Cache miss
    fi

    local cache_file=$(echo "$cache_entry" | cut -d'|' -f4)
    local cache_timestamp=$(echo "$cache_entry" | cut -d'|' -f3)
    local current_time=$(date +%s)
    local cache_age=$((current_time - cache_timestamp))

    if [[ $cache_age -gt $ttl ]]; then
        # Cache expired, remove it
        rm -f "$cache_file" 2>/dev/null
        sed -i "/^$cache_key/d" "$CACHE_INDEX" 2>/dev/null
        return 1  # Cache miss (expired)
    fi

    if [[ -f "$cache_file" ]]; then
        echo "$cache_file"
        return 0  # Cache hit
    fi

    return 1  # Cache miss (file missing)
}

# Store result in cache
store_cache() {
    local target="$1"
    local scan_type="$2"
    local scan_params="${3:-default}"
    local result_file="$4"

    init_cache

    local cache_key=$(generate_cache_key "$target" "$scan_type" "$scan_params")
    local timestamp=$(date +%s)
    local cache_file="$CACHE_DIR/${cache_key}.cache"

    # Copy result to cache
    cp "$result_file" "$cache_file" 2>/dev/null

    # Update index
    sed -i "/^$cache_key/d" "$CACHE_INDEX" 2>/dev/null
    echo "$cache_key|$scan_type|$timestamp|$cache_file" >> "$CACHE_INDEX"

    echo "✅ Result cached: $cache_file"
}

# Clear expired cache entries
clear_expired_cache() {
    local ttl="${1:-$CACHE_TTL}"
    local current_time=$(date +%s)

    init_cache

    while IFS='|' read -r cache_key scan_type timestamp cache_file; do
        if [[ "$cache_key" =~ ^# ]] || [[ -z "$cache_key" ]]; then
            continue
        fi

        local cache_age=$((current_time - timestamp))
        if [[ $cache_age -gt $ttl ]]; then
            rm -f "$cache_file" 2>/dev/null
            sed -i "/^$cache_key/d" "$CACHE_INDEX" 2>/dev/null
        fi
    done < "$CACHE_INDEX"

    echo "✅ Expired cache entries cleared"
}

# Clear all cache
clear_all_cache() {
    rm -rf "$CACHE_DIR"/*
    init_cache
    echo "✅ All cache cleared"
}

# Show cache statistics
cache_stats() {
    init_cache

    local total_entries=0
    local total_size=0

    while IFS='|' read -r cache_key scan_type timestamp cache_file; do
        if [[ "$cache_key" =~ ^# ]] || [[ -z "$cache_key" ]]; then
            continue
        fi

        if [[ -f "$cache_file" ]]; then
            total_entries=$((total_entries + 1))
            total_size=$((total_size + $(stat -f%z "$cache_file" 2>/dev/null || stat -c%s "$cache_file" 2>/dev/null)))
        fi
    done < "$CACHE_INDEX"

    echo "═════════════════════════════════════════════════════════"
    echo "CACHE STATISTICS"
    echo "═════════════════════════════════════════════════════════"
    echo "Total Entries: $total_entries"
    echo "Total Size: $((total_size / 1024)) KB"
    echo "Cache Directory: $CACHE_DIR"
    echo "═════════════════════════════════════════════════════════"
}

# Export functions for use in other scripts
export -f init_cache
export -f generate_cache_key
export -f check_cache
export -f store_cache
export -f clear_expired_cache
export -f clear_all_cache
export -f cache_stats

# CLI interface
case "${1:-}" in
    check)
        check_cache "$2" "$3" "$4" "$5"
        ;;
    store)
        store_cache "$2" "$3" "$4" "$5"
        ;;
    clear-expired)
        clear_expired_cache "$2"
        ;;
    clear-all)
        clear_all_cache
        ;;
    stats)
        cache_stats
        ;;
    *)
        echo "Usage: $0 {check|store|clear-expired|clear-all|stats} [args...]"
        echo ""
        echo "Commands:"
        echo "  check <target> <scan_type> [scan_params] [ttl]  - Check if cached result exists"
        echo "  store <target> <scan_type> [scan_params] <file>  - Store result in cache"
        echo "  clear-expired [ttl]                              - Clear expired entries"
        echo "  clear-all                                        - Clear all cache"
        echo "  stats                                            - Show cache statistics"
        exit 1
        ;;
esac
