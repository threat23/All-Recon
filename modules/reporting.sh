#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - ENHANCED REPORTING MODULE
# Generates comprehensive scan reports in multiple formats (TXT, JSON, HTML, CSV)
# Philosophy: Beautiful output = faster analysis = better decisions
# ═══════════════════════════════════════════════════════════════════

# Source validation module if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/validation.sh" ]]; then
    source "$SCRIPT_DIR/validation.sh"
    setup_signal_traps
fi

REPORT_DIR="output/reports"
mkdir -p "$REPORT_DIR"

# Risk scoring system
HIGH_RISK_PORTS="22 445 3389 5985 5986 8080 9200 23 21 25 53 135 139 443"
MEDIUM_RISK_PORTS="80 81 443 8080 8443 3000 5000 8000 8888"
LOW_RISK_PORTS="110 143 993 995 587 465"

# Helper function to calculate risk score
calculate_risk_score() {
    local scanfile="$1"
    local score=0
    local high_count=0
    local medium_count=0
    local low_count=0

    # Count high-risk ports
    local high_pattern=$(echo $HIGH_RISK_PORTS | tr ' ' '|')
    high_count=$(grep -E "^($high_pattern)/.*open" "$scanfile" 2>/dev/null | wc -l)
    score=$((score + high_count * 10))

    # Count medium-risk ports
    local medium_pattern=$(echo $MEDIUM_RISK_PORTS | tr ' ' '|')
    medium_count=$(grep -E "^($medium_pattern)/.*open" "$scanfile" 2>/dev/null | wc -l)
    score=$((score + medium_count * 5))

    # Count low-risk ports
    local low_pattern=$(echo $LOW_RISK_PORTS | tr ' ' '|')
    low_count=$(grep -E "^($low_pattern)/.*open" "$scanfile" 2>/dev/null | wc -l)
    score=$((score + low_count * 2))

    echo "$score"
}

# Generate text report
generate_text_report() {
    local scan_dir="$1"
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
        local host_count
        host_count=$(find "$scan_dir" -name "host_*.txt" -type f 2>/dev/null | wc -l)
        echo "Total Hosts Scanned: $host_count"

        # Calculate overall risk score
        local total_risk=0
        local hosts_with_risk=0
        for scanfile in "$scan_dir"/host_*.txt; do
            if [[ -f "$scanfile" ]]; then
                local risk=$(calculate_risk_score "$scanfile")
                if [[ $risk -gt 0 ]]; then
                    total_risk=$((total_risk + risk))
                    hosts_with_risk=$((hosts_with_risk + 1))
                fi
            fi
        done
        echo "Overall Risk Score: $total_risk"
        echo "Hosts with Open Ports: $hosts_with_risk"
        echo ""

        echo "───────────────────────────────────────────────────────────────────"
        echo "DETAILED FINDINGS"
        echo "───────────────────────────────────────────────────────────────────"
        echo ""

        # Safely loop over scan files
        local found_scans=0
        for scanfile in "$scan_dir"/host_*.txt; do
            if [[ -f "$scanfile" ]]; then
                found_scans=1
                local risk=$(calculate_risk_score "$scanfile")
                local risk_level="LOW"
                [[ $risk -ge 30 ]] && risk_level="HIGH"
                [[ $risk -ge 10 && $risk -lt 30 ]] && risk_level="MEDIUM"

                echo "📊 $(basename "$scanfile")"
                echo "   Risk Score: $risk ($risk_level)"
                echo "---"
                grep -E "^[0-9]+/.*open" "$scanfile" 2>/dev/null | head -15
                echo ""
            fi
        done

        if [[ $found_scans -eq 0 ]]; then
            echo "No host scan results found in $scan_dir"
            echo ""
        fi

        echo "───────────────────────────────────────────────────────────────────"
        echo "HIGH-RISK FINDINGS"
        echo "───────────────────────────────────────────────────────────────────"

        # High-risk ports
        local high_risk_found=0
        local high_risk_pattern=$(echo $HIGH_RISK_PORTS | tr ' ' '|')
        for scanfile in "$scan_dir"/host_*.txt; do
            if [[ -f "$scanfile" ]]; then
                local high_ports=$(grep -E "^($high_risk_pattern)/.*open" "$scanfile" 2>/dev/null)
                if [[ -n "$high_ports" ]]; then
                    high_risk_found=1
                    echo "⚠️  HIGH RISK SERVICE FOUND IN: $scanfile"
                    echo "$high_ports"
                    echo ""
                fi
            fi
        done

        [[ $high_risk_found -eq 0 ]] && echo "No high-risk services detected."

        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "END OF REPORT"
        echo "═══════════════════════════════════════════════════════════════════"

    } > "$report_file"

    echo "✅ Text report generated: $report_file"
    echo "$report_file"
}

# Generate JSON report
generate_json_report() {
    local scan_dir="$1"
    local report_file="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).json"

    echo "Generating JSON report..."

    # Start JSON structure
    cat > "$report_file" << EOF
{
  "report_metadata": {
    "generated_at": "$(date -Iseconds)",
    "scan_directory": "$scan_dir",
    "tool": "ALL-RECON",
    "version": "2.0"
  },
  "executive_summary": {
    "total_hosts_scanned": $(find "$scan_dir" -name "host_*.txt" -type f 2>/dev/null | wc -l),
    "total_risk_score": 0,
    "hosts_with_open_ports": 0
  },
  "hosts": [
EOF

    local first_host=true
    local total_risk=0
    local hosts_with_risk=0

    for scanfile in "$scan_dir"/host_*.txt; do
        if [[ -f "$scanfile" ]]; then
            [[ $first_host == false ]] && echo "," >> "$report_file"
            first_host=false

            local hostname=$(basename "$scanfile" .txt | sed 's/host_//')
            local risk=$(calculate_risk_score "$scanfile")
            local risk_level="LOW"
            [[ $risk -ge 30 ]] && risk_level="HIGH"
            [[ $risk -ge 10 && $risk -lt 30 ]] && risk_level="MEDIUM"

            [[ $risk -gt 0 ]] && hosts_with_risk=$((hosts_with_risk + 1))
            total_risk=$((total_risk + risk))

            # Extract open ports as a simple array string
            local ports_array=$(grep -E "^[0-9]+/.*open" "$scanfile" 2>/dev/null | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')

            if [[ -z "$ports_array" ]]; then
                cat >> "$report_file" << EOF
    {
      "hostname": "$hostname",
      "scan_file": "$(basename "$scanfile")",
      "risk_score": $risk,
      "risk_level": "$risk_level",
      "open_ports": []
    }
EOF
            else
                cat >> "$report_file" << EOF
    {
      "hostname": "$hostname",
      "scan_file": "$(basename "$scanfile")",
      "risk_score": $risk,
      "risk_level": "$risk_level",
      "open_ports": ["${ports_array}"]
    }
EOF
            fi
        fi
    done

    # Close JSON structure
    cat >> "$report_file" << EOF
  ],
  "high_risk_findings": [
EOF

    local first_finding=true
    local high_risk_pattern=$(echo $HIGH_RISK_PORTS | tr ' ' '|')
    for scanfile in "$scan_dir"/host_*.txt; do
        if [[ -f "$scanfile" ]]; then
            local high_ports=$(grep -E "^($high_risk_pattern)/.*open" "$scanfile" 2>/dev/null)
            if [[ -n "$high_ports" ]]; then
                [[ $first_finding == false ]] && echo "," >> "$report_file"
                first_finding=false

                cat >> "$report_file" << EOF
    {
      "host": "$(basename "$scanfile")",
      "ports": "$(echo "$high_ports" | tr '\n' ';' | sed 's/;$//')"
    }
EOF
            fi
        fi
    done

    cat >> "$report_file" << EOF
  ]
}
EOF

    # Update executive summary with calculated values
    if command -v jq &>/dev/null; then
        temp_file=$(mktemp)
        jq ".executive_summary.total_risk_score = $total_risk | .executive_summary.hosts_with_open_ports = $hosts_with_risk" "$report_file" > "$temp_file"
        mv "$temp_file" "$report_file"
    fi

    echo "✅ JSON report generated: $report_file"
    echo "$report_file"
}

# Generate CSV report
generate_csv_report() {
    local scan_dir="$1"
    local report_file="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).csv"

    echo "Generating CSV report..."

    # CSV Header
    echo "Hostname,Scan_File,Risk_Score,Risk_Level,Open_Ports,High_Risk_Ports" > "$report_file"

    for scanfile in "$scan_dir"/host_*.txt; do
        if [[ -f "$scanfile" ]]; then
            local hostname=$(basename "$scanfile" .txt | sed 's/host_//')
            local scanfile_name=$(basename "$scanfile")
            local risk=$(calculate_risk_score "$scanfile")
            local risk_level="LOW"
            [[ $risk -ge 30 ]] && risk_level="HIGH"
            [[ $risk -ge 10 && $risk -lt 30 ]] && risk_level="MEDIUM"

            local open_ports=$(grep -E "^[0-9]+/.*open" "$scanfile" 2>/dev/null | cut -d'/' -f1 | tr '\n' ';' | sed 's/;$//')
            local high_risk_pattern=$(echo $HIGH_RISK_PORTS | tr ' ' '|')
            local high_ports=$(grep -E "^($high_risk_pattern)/.*open" "$scanfile" 2>/dev/null | cut -d'/' -f1 | tr '\n' ';' | sed 's/;$//')

            printf '%s,%s,%d,%s,%s,%s\n' "$hostname" "$scanfile_name" "$risk" "$risk_level" "$open_ports" "$high_ports" >> "$report_file"
        fi
    done

    echo "✅ CSV report generated: $report_file"
    echo "$report_file"
}

# Generate HTML report
generate_html_report() {
    local scan_dir="$1"
    local report_file="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).html"

    echo "Generating HTML report..."

    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ALL-RECON Scan Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #e0e0e0;
            line-height: 1.6;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            text-align: center;
            padding: 40px 20px;
            background: rgba(31, 111, 235, 0.1);
            border-radius: 10px;
            margin-bottom: 30px;
            border: 1px solid #1f6feb;
        }
        .header h1 {
            color: #39ff14;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p { color: #888; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: rgba(26, 34, 44, 0.8);
            padding: 20px;
            border-radius: 8px;
            border: 1px solid #1a222c;
            text-align: center;
        }
        .summary-card h3 { color: #1f6feb; margin-bottom: 10px; }
        .summary-card .value { font-size: 2em; font-weight: bold; color: #39ff14; }
        .section {
            background: rgba(26, 34, 44, 0.8);
            padding: 25px;
            border-radius: 8px;
            margin-bottom: 30px;
            border: 1px solid #1a222c;
        }
        .section h2 {
            color: #39ff14;
            margin-bottom: 20px;
            border-bottom: 2px solid #1f6feb;
            padding-bottom: 10px;
        }
        .host-card {
            background: rgba(11, 15, 20, 0.8);
            padding: 20px;
            margin-bottom: 15px;
            border-radius: 6px;
            border-left: 4px solid #39ff14;
        }
        .host-card.high-risk { border-left-color: #ff4444; }
        .host-card.medium-risk { border-left-color: #ffaa00; }
        .host-card h3 { color: #e0e0e0; margin-bottom: 10px; }
        .risk-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }
        .risk-high { background: #ff4444; color: #fff; }
        .risk-medium { background: #ffaa00; color: #000; }
        .risk-low { background: #39ff14; color: #000; }
        .ports-list {
            margin-top: 15px;
            font-family: 'Consolas', monospace;
            font-size: 0.9em;
            color: #888;
        }
        .high-risk-section {
            border: 2px solid #ff4444;
        }
        .high-risk-section h2 { color: #ff4444; border-bottom-color: #ff4444; }
        .high-risk-item {
            background: rgba(255, 68, 68, 0.1);
            padding: 15px;
            margin-bottom: 10px;
            border-radius: 6px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #1a222c;
        }
        th { color: #1f6feb; }
        tr:hover { background: rgba(31, 111, 235, 0.1); }
        .footer {
            text-align: center;
            padding: 20px;
            color: #888;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>ALL-RECON Scan Report</h1>
            <p>Generated: <span id="report-date"></span></p>
        </div>

        <div class="summary">
            <div class="summary-card">
                <h3>Total Hosts</h3>
                <div class="value" id="total-hosts">0</div>
            </div>
            <div class="summary-card">
                <h3>Risk Score</h3>
                <div class="value" id="total-risk">0</div>
            </div>
            <div class="summary-card">
                <h3>Hosts with Ports</h3>
                <div class="value" id="hosts-with-ports">0</div>
            </div>
        </div>

        <div class="section">
            <h2>Detailed Findings</h2>
            <div id="hosts-container"></div>
        </div>

        <div class="section high-risk-section">
            <h2>High-Risk Findings</h2>
            <div id="high-risk-container"></div>
        </div>

        <div class="footer">
            <p>Generated by ALL-RECON | Automated Security Assessment Tool</p>
        </div>
    </div>

    <script>
        const scanData = {
EOF

    # Add data
    local total_hosts=0
    local total_risk=0
    local hosts_with_ports=0
    local hosts_json="["
    local high_risk_json="["
    local first_host=true
    local first_high=true

    for scanfile in "$scan_dir"/host_*.txt; do
        if [[ -f "$scanfile" ]]; then
            local hostname=$(basename "$scanfile" .txt | sed 's/host_//')
            local risk=$(calculate_risk_score "$scanfile")
            local risk_level="LOW"
            [[ $risk -ge 30 ]] && risk_level="HIGH"
            [[ $risk -ge 10 && $risk -lt 30 ]] && risk_level="MEDIUM"

            total_hosts=$((total_hosts + 1))
            [[ $risk -gt 0 ]] && hosts_with_ports=$((hosts_with_ports + 1))
            total_risk=$((total_risk + risk))

            local open_ports=$(grep -E "^[0-9]+/.*open" "$scanfile" 2>/dev/null | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
            local high_risk_pattern=$(echo $HIGH_RISK_PORTS | tr ' ' '|')
            local high_ports=$(grep -E "^($high_risk_pattern)/.*open" "$scanfile" 2>/dev/null | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')

            [[ $first_host == false ]] && hosts_json="$hosts_json,"
            first_host=false
            hosts_json="$hosts_json{\"hostname\":\"$hostname\",\"risk\":$risk,\"risk_level\":\"$risk_level\",\"ports\":\"$open_ports\"}"

            if [[ -n "$high_ports" ]]; then
                [[ $first_high == false ]] && high_risk_json="$high_risk_json,"
                first_high=false
                high_risk_json="$high_risk_json{\"host\":\"$hostname\",\"ports\":\"$high_ports\"}"
            fi
        fi
    done

    hosts_json="$hosts_json]"
    high_risk_json="$high_risk_json]"

    cat >> "$report_file" << EOF
            totalHosts: $total_hosts,
            totalRisk: $total_risk,
            hostsWithPorts: $hosts_with_ports,
            hosts: $hosts_json,
            highRisk: $high_risk_json
        };

        document.getElementById('report-date').textContent = new Date().toLocaleString();
        document.getElementById('total-hosts').textContent = scanData.totalHosts;
        document.getElementById('total-risk').textContent = scanData.totalRisk;
        document.getElementById('hosts-with-ports').textContent = scanData.hostsWithPorts;

        const hostsContainer = document.getElementById('hosts-container');
        scanData.hosts.forEach(host => {
            const riskClass = host.risk_level.toLowerCase() + '-risk';
            const card = document.createElement('div');
            card.className = 'host-card ' + riskClass;
            card.innerHTML = '<h3>' + host.hostname + '</h3>' +
                '<span class="risk-badge risk-' + host.risk_level.toLowerCase() + '">' + host.risk_level + ' - Score: ' + host.risk + '</span>' +
                '<div class="ports-list">' + (host.ports || 'No open ports detected') + '</div>';
            hostsContainer.appendChild(card);
        });

        const highRiskContainer = document.getElementById('high-risk-container');
        if (scanData.highRisk.length === 0) {
            highRiskContainer.innerHTML = '<p>No high-risk services detected.</p>';
        } else {
            scanData.highRisk.forEach(item => {
                const div = document.createElement('div');
                div.className = 'high-risk-item';
                div.innerHTML = '<strong>' + item.host + '</strong><br>' + item.ports;
                highRiskContainer.appendChild(div);
            });
        }
    </script>
</body>
</html>
EOF

    echo "✅ HTML report generated: $report_file"
    echo "$report_file"
}

# Generate all report formats
generate_all_reports() {
    local scan_dir="$1"
    echo "Generating all report formats..."
    generate_text_report "$scan_dir"
    generate_json_report "$scan_dir"
    generate_csv_report "$scan_dir"
    generate_html_report "$scan_dir"
}

# List existing reports
list_reports() {
    echo "📁 Available Reports:"
    echo ""
    echo "Text Reports:"
    ls -1t "$REPORT_DIR"/*.txt 2>/dev/null | head -5 || echo "  No text reports found"
    echo ""
    echo "JSON Reports:"
    ls -1t "$REPORT_DIR"/*.json 2>/dev/null | head -5 || echo "  No JSON reports found"
    echo ""
    echo "CSV Reports:"
    ls -1t "$REPORT_DIR"/*.csv 2>/dev/null | head -5 || echo "  No CSV reports found"
    echo ""
    echo "HTML Reports:"
    ls -1t "$REPORT_DIR"/*.html 2>/dev/null | head -5 || echo "  No HTML reports found"
}

# Main execution
usage() {
    echo "Usage: $0 [OPTIONS] [scan_directory]"
    echo ""
    echo "Options:"
    echo "  text      Generate text report (default)"
    echo "  json      Generate JSON report"
    echo "  csv       Generate CSV report"
    echo "  html      Generate HTML report"
    echo "  all       Generate all report formats"
    echo "  list      List available reports"
    echo ""
    echo "Examples:"
    echo "  $0 output                    # Generate text report"
    echo "  $0 json output               # Generate JSON report"
    echo "  $0 html output               # Generate HTML report"
    echo "  $0 all output                # Generate all formats"
    echo "  $0 list                      # List existing reports"
    exit 1
}

if [[ $# -eq 0 ]]; then
    generate_text_report "output"
elif [[ "$1" == "list" ]]; then
    list_reports
elif [[ "$1" == "text" ]]; then
    generate_text_report "${2:-output}"
elif [[ "$1" == "json" ]]; then
    generate_json_report "${2:-output}"
elif [[ "$1" == "csv" ]]; then
    generate_csv_report "${2:-output}"
elif [[ "$1" == "html" ]]; then
    generate_html_report "${2:-output}"
elif [[ "$1" == "all" ]]; then
    generate_all_reports "${2:-output}"
else
    # Default to text report for backward compatibility
    generate_text_report "$1"
fi
