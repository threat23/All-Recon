#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - SUBDOMAIN CLEANER & DEDUPLICATOR
# Clean and organize subdomain discovery results
# Remove duplicates, invalid entries, and unnecessary data
# ═══════════════════════════════════════════════════════════════════

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

CLEAN_LOG="logs/subdomain_clean_$(date +%Y%m%d_%H%M%S).log"
CLEAN_OUTPUT="output/clean_subdomains_$(date +%Y%m%d_%H%M%S)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p logs output "$CLEAN_OUTPUT"

log_clean() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$CLEAN_LOG"
}

# Function: Extract subdomains from results
extract_subdomains() {
    local input_dir=$1
    local output_file="$CLEAN_OUTPUT/extracted_subdomains_$TIMESTAMP.txt"
    
    log_clean "[SCAN] Extracting subdomains from results..."
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "EXTRACTED SUBDOMAINS"
        echo "Extracted: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        # Extract from common_subdomains file
        grep -h "^[OK] FOUND:" "$input_dir"/common_subdomains_*.txt 2>/dev/null | \
        sed 's/[OK] FOUND: //' | sed 's/ *$//' | sort -u
        
        # Extract from other sources
        grep -hE "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "$input_dir"/*.txt 2>/dev/null | sort -u
        
    } | sort -u > "$output_file"
    
    local count=$(wc -l < "$output_file")
    log_clean "[OK] Extracted $count subdomains"
    
    echo "$output_file"
}

# Function: Remove duplicates and resolve IPs
deduplicate_and_resolve() {
    local input_file=$1
    local output_file="$CLEAN_OUTPUT/deduplicated_${TIMESTAMP}.txt"
    
    log_clean "[CLEAN] Deduplicating and resolving IPs..."
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "CLEAN SUBDOMAIN LIST WITH IP RESOLUTION"
        echo "Cleaned: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "SUBDOMAIN                          | IP ADDRESS         | STATUS"
        echo "───────────────────────────────────┼────────────────────┼──────────"
        
        local resolved=0
        local unresolved=0
        local duplicates=0
        local processed=()
        
        while IFS= read -r subdomain; do
            [[ -z "$subdomain" ]] && continue
            
            # Check if already processed (dedup)
            if [[ " ${processed[@]} " =~ " ${subdomain} " ]]; then
                ((duplicates++))
                continue
            fi
            
            processed+=("$subdomain")
            
            # Attempt DNS resolution
            ip=$(dig +short "$subdomain" A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
            
            if [[ -n "$ip" ]]; then
                printf "%-35s | %-18s | [OK] ACTIVE\n" "$subdomain" "$ip"
                ((resolved++))
            else
                printf "%-35s | %-18s | [WARN]  UNRESOLVED\n" "$subdomain" "N/A"
                ((unresolved++))
            fi
        done < "$input_file"
        
        echo ""
        echo "───────────────────────────────────┴────────────────────┴──────────"
        echo "Summary:"
        echo "  [OK] Resolved:     $resolved"
        echo "  [WARN]  Unresolved:   $unresolved"
        echo "  [DELETE]  Duplicates:   $duplicates"
        
    } | tee "$output_file"
    
    log_clean "[OK] Deduplication complete"
    echo "$output_file"
}

# Function: Filter by active hosts only
filter_active_only() {
    local input_file=$1
    local output_file="$CLEAN_OUTPUT/active_subdomains_${TIMESTAMP}.txt"
    
    log_clean "[TARGET] Filtering for active hosts only..."
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "ACTIVE SUBDOMAINS ONLY"
        echo "Filtered: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "SUBDOMAIN                          | IP ADDRESS"
        echo "───────────────────────────────────┼────────────────────"
        
        local active_count=0
        
        grep "[OK] ACTIVE" "$input_file" | while read -r line; do
            subdomain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
            
            if [[ -n "$ip" && "$ip" != "N/A" ]]; then
                printf "%-35s | %-18s\n" "$subdomain" "$ip"
                ((active_count++))
            fi
        done
        
        echo ""
        echo "───────────────────────────────────┴────────────────────"
        
    } | tee "$output_file"
    
    log_clean "[OK] Active filter complete"
    echo "$output_file"
}

# Function: Group by IP address
group_by_ip() {
    local input_file=$1
    local output_file="$CLEAN_OUTPUT/grouped_by_ip_${TIMESTAMP}.txt"
    
    log_clean "[LINK] Grouping subdomains by IP address..."
    
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "SUBDOMAINS GROUPED BY IP ADDRESS"
        echo "Grouped: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        # Extract unique IPs
        grep "[OK] ACTIVE" "$input_file" | \
        awk -F'|' '{print $2}' | xargs | sort -u | while read -r ip; do
            [[ -z "$ip" || "$ip" == "N/A" ]] && continue
            
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "IP: $ip"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            grep "[OK] ACTIVE" "$input_file" | \
            awk -v target_ip="$ip" -F'|' '$2 ~ target_ip {print $1}' | \
            sed 's/^ */  /'
            
            echo ""
        done
        
    } | tee "$output_file"
    
    log_clean "[OK] Grouping complete"
    echo "$output_file"
}

# Function: Generate CSV export
export_to_csv() {
    local input_file=$1
    local output_file="$CLEAN_OUTPUT/subdomains_${TIMESTAMP}.csv"
    
    log_clean "[REPORT] Exporting to CSV format..."
    
    {
        echo "subdomain,ip_address,status,resolved_date"
        
        grep "[OK] ACTIVE\|[WARN]" "$input_file" | while read -r line; do
            subdomain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
            status=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            
            echo "$subdomain,$ip,$status,$(date)"
        done
        
    } | tee "$output_file"
    
    log_clean "[OK] CSV export complete: $output_file"
    echo "$output_file"
}

# Function: Generate JSON export
export_to_json() {
    local input_file=$1
    local output_file="$CLEAN_OUTPUT/subdomains_${TIMESTAMP}.json"
    
    log_clean "[REPORT] Exporting to JSON format..."
    
    {
        echo "{"
        echo '  "subdomains": ['
        
        local first=true
        grep "[OK] ACTIVE\|[WARN]" "$input_file" | while read -r line; do
            subdomain=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
            status=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
            
            if [[ "$first" == "false" ]]; then
                echo ","
            fi
            first=false
            
            echo -n '    {'
            echo -n "\"subdomain\": \"$subdomain\", "
            echo -n "\"ip\": \"$ip\", "
            echo -n "\"status\": \"$status\""
            echo -n '}'
        done
        
        echo ""
        echo "  ]"
        echo "}"
        
    } | tee "$output_file"
    
    log_clean "[OK] JSON export complete: $output_file"
    echo "$output_file"
}

# Function: Comprehensive cleaning pipeline
comprehensive_clean() {
    local input_dir=$1
    
    log_clean "[CLEAN] Starting comprehensive subdomain cleaning pipeline..."
    
    # Step 1: Extract
    extracted=$(extract_subdomains "$input_dir")
    
    # Step 2: Deduplicate and resolve
    deduplicated=$(deduplicate_and_resolve "$extracted")
    
    # Step 3: Filter active
    active=$(filter_active_only "$deduplicated")
    
    # Step 4: Group by IP
    grouped=$(group_by_ip "$deduplicated")
    
    # Step 5: Export formats
    csv=$(export_to_csv "$deduplicated")
    json=$(export_to_json "$deduplicated")
    
    # Generate summary
    summary_file="$CLEAN_OUTPUT/CLEANING_SUMMARY_$TIMESTAMP.txt"
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "SUBDOMAIN CLEANING SUMMARY"
        echo "Cleaned: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "[DIR] Input Directory: $input_dir"
        echo ""
        echo "[LIST] Generated Files:"
        echo "  - extracted_subdomains_*.txt - All unique subdomains"
        echo "  - deduplicated_*.txt         - With IP resolution"
        echo "  - active_subdomains_*.txt    - Only resolved hosts"
        echo "  - grouped_by_ip_*.txt        - Organized by IP"
        echo "  - subdomains_*.csv           - CSV format"
        echo "  - subdomains_*.json          - JSON format"
        echo ""
        echo "[REPORT] Statistics:"
        echo "  Total extracted: $(wc -l < "$extracted")"
        echo "  After dedup: $(grep -c "[OK]\|[WARN]" "$deduplicated" 2>/dev/null || echo "0")"
        echo "  Active hosts: $(grep -c "[OK] ACTIVE" "$deduplicated" 2>/dev/null || echo "0")"
        echo ""
        echo "[SAVE] All results in: $CLEAN_OUTPUT/"
        echo "[LIST] Log file: $CLEAN_LOG"
        
    } | tee "$summary_file"
    
    log_clean "[OK] Comprehensive cleaning complete!"
}

# Main execution
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_directory> [action]"
    echo ""
    echo "Actions:"
    echo "  extract      - Extract subdomains only"
    echo "  deduplicate  - Deduplicate and resolve IPs"
    echo "  active       - Filter active hosts only"
    echo "  group        - Group subdomains by IP"
    echo "  csv          - Export to CSV"
    echo "  json         - Export to JSON"
    echo "  all          - Comprehensive cleaning (default)"
    echo ""
    echo "Examples:"
    echo "  $0 output/subdomains_20260609_154200/ all"
    echo "  $0 output/subdomains_20260609_154200/ active"
    echo "  $0 output/subdomains_20260609_154200/ csv"
    exit 1
fi

INPUT_DIR=$1
ACTION=${2:-all}

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "[ERROR] Input directory not found: $INPUT_DIR"
    exit 1
fi

case $ACTION in
    extract)
        extract=$(extract_subdomains "$INPUT_DIR")
        echo ""
        echo "[OK] Extraction complete: $extract"
        ;;
    deduplicate)
        extracted=$(extract_subdomains "$INPUT_DIR")
        deduplicated=$(deduplicate_and_resolve "$extracted")
        echo ""
        echo "[OK] Deduplication complete: $deduplicated"
        ;;
    active)
        extracted=$(extract_subdomains "$INPUT_DIR")
        deduplicated=$(deduplicate_and_resolve "$extracted")
        active=$(filter_active_only "$deduplicated")
        echo ""
        echo "[OK] Filtering complete: $active"
        ;;
    group)
        extracted=$(extract_subdomains "$INPUT_DIR")
        deduplicated=$(deduplicate_and_resolve "$extracted")
        grouped=$(group_by_ip "$deduplicated")
        echo ""
        echo "[OK] Grouping complete: $grouped"
        ;;
    csv)
        extracted=$(extract_subdomains "$INPUT_DIR")
        deduplicated=$(deduplicate_and_resolve "$extracted")
        csv=$(export_to_csv "$deduplicated")
        echo ""
        echo "[OK] CSV export complete: $csv"
        ;;
    json)
        extracted=$(extract_subdomains "$INPUT_DIR")
        deduplicated=$(deduplicate_and_resolve "$extracted")
        json=$(export_to_json "$deduplicated")
        echo ""
        echo "[OK] JSON export complete: $json"
        ;;
    all)
        comprehensive_clean "$INPUT_DIR"
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac

echo ""
echo "[DIR] Results saved to: $CLEAN_OUTPUT/"
echo "[LIST] Log file: $CLEAN_LOG"
