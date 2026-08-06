#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - REPORTING MODULE
# Generates comprehensive scan reports from collected data
# Philosophy: Beautiful output = faster analysis = better decisions
# ═══════════════════════════════════════════════════════════════════

REPORT_DIR="output/reports"
mkdir -p "$REPORT_DIR"

generate_report() {
    local scan_dir=${1:-.}
    local report_file="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "═══════════════════════════════════════════════════════════════════"
        echo "ALL-RECON - COMPREHENSIVE SCAN REPORT"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Scan Directory: $scan_dir"
        echo ""
        
        echo "───────────────────────────────────────────────────────────────────"
        echo "EXECUTIVE SUMMARY"
        echo "───────────────────────────────────────────────────────────────────"
        
        # Count hosts scanned
        host_count=$(find "$scan_dir" -name "*.txt" -type f | wc -l)
        echo "Total Hosts Scanned: $host_count"
        echo ""
        
        echo "───────────────────────────────────────────────────────────────────"
        echo "DETAILED FINDINGS"
        echo "───────────────────────────────────────────────────────────────────"
        echo ""
        
        # Extract key findings from scan results
        for scanfile in "$scan_dir"/host_*.txt; do
            if [[ -f "$scanfile" ]]; then
                echo "📊 $(basename "$scanfile")"
                echo "---"
                grep -E "^[0-9]+/.*open" "$scanfile" 2>/dev/null | head -10
                echo ""
            fi
        done
        
        echo "───────────────────────────────────────────────────────────────────"
        echo "HIGH-RISK FINDINGS"
        echo "───────────────────────────────────────────────────────────────────"
        
        # High-risk ports
        for scanfile in "$scan_dir"/host_*.txt; do
            if [[ -f "$scanfile" ]]; then
                grep -E "^(22|445|3389|5985|5986)/.*open" "$scanfile" 2>/dev/null && \
                    echo "⚠️  HIGH RISK SERVICE FOUND IN: $scanfile"
            fi
        done
        
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "END OF REPORT"
        echo "═══════════════════════════════════════════════════════════════════"
        
    } > "$report_file"
    
    echo "✅ Report generated: $report_file"
    cat "$report_file"
}

# List existing reports
list_reports() {
    echo "📁 Available Reports:"
    ls -1t "$REPORT_DIR"/*.txt 2>/dev/null | head -10 || echo "No reports found"
}

# Main execution
if [[ $# -eq 0 ]]; then
    generate_report "output"
elif [[ "$1" == "list" ]]; then
    list_reports
else
    generate_report "$1"
fi
