#!/bin/bash

# ===================================================================
# ALL-RECON AUTOMATED TEST SUITE
# Framework for unit and integration testing of all modules & scripts
# ===================================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

cd "$PROJECT_ROOT" || exit 1

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

log_pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    ((FAILED_TESTS++))
}

log_skip() {
    echo -e "  [${YELLOW}SKIP${NC}] $1"
    ((SKIPPED_TESTS++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        log_pass "$msg"
    else
        log_fail "$msg (Expected: '$expected', Actual: '$actual')"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local msg="$3"
    if [[ "$expected_code" -eq "$actual_code" ]]; then
        log_pass "$msg"
    else
        log_fail "$msg (Expected exit code: $expected_code, Actual: $actual_code)"
    fi
}

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       ALL-RECON AUTOMATED TEST RUNNER              ${NC}"
echo -e "${BLUE}====================================================${NC}\n"

# -------------------------------------------------------------------
# TEST SUITE 1: BASH SYNTAX VALIDATION
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 1: Bash Syntax Validation (bash -n)${NC}"

script_files=(
    "all_recon.sh"
    "all_recon_alt.sh"
    "install.sh"
    "modules/validation.sh"
    "modules/recon.sh"
    "modules/subdomain_finder.sh"
    "modules/subdomain_cleaner.sh"
    "modules/web_vulnerabilities.sh"
    "modules/reporting.sh"
    "modules/batch_runner.sh"
    "modules/whois_recon.sh"
    "modules/passive.sh"
    "CLEANER_GUIDE.sh"
    "QUICKSTART.sh"
    "START_HERE.sh"
    "SUBDOMAIN_GUIDE.sh"
    "TEST_SUBDOMAIN.sh"
)

for file in "${script_files[@]}"; do
    if [[ -f "$file" ]]; then
        bash -n "$file" &>/dev/null
        assert_exit_code 0 $? "Syntax check: $file"
    else
        log_skip "File not found for syntax check: $file"
    fi
done
echo ""

# -------------------------------------------------------------------
# TEST SUITE 2: INPUT VALIDATION MODULE (modules/validation.sh)
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 2: Input Validation Helper Unit Tests${NC}"

if [[ -f "modules/validation.sh" ]]; then
    source "modules/validation.sh"

    # Test IP Validation
    is_valid_ip "192.168.1.1"
    assert_exit_code 0 $? "is_valid_ip: 192.168.1.1 should be valid"

    is_valid_ip "8.8.8.8"
    assert_exit_code 0 $? "is_valid_ip: 8.8.8.8 should be valid"

    is_valid_ip "999.999.999.999"
    assert_exit_code 1 $? "is_valid_ip: 999.999.999.999 should be invalid"

    is_valid_ip "not_an_ip"
    assert_exit_code 1 $? "is_valid_ip: 'not_an_ip' should be invalid"

    # Test Domain Validation
    is_valid_domain "example.com"
    assert_exit_code 0 $? "is_valid_domain: example.com should be valid"

    is_valid_domain "sub.domain.co.uk"
    assert_exit_code 0 $? "is_valid_domain: sub.domain.co.uk should be valid"

    is_valid_domain "invalid..domain"
    assert_exit_code 1 $? "is_valid_domain: invalid..domain should be invalid"

    is_valid_domain "http://example.com"
    assert_exit_code 1 $? "is_valid_domain: http://example.com (with scheme) should be invalid"

    # Test URL Validation
    is_valid_url "http://example.com"
    assert_exit_code 0 $? "is_valid_url: http://example.com should be valid"

    is_valid_url "https://sub.target.org:8080/path?arg=1"
    assert_exit_code 0 $? "is_valid_url: https://sub.target.org:8080/path should be valid"

    is_valid_url "ftp://example.com"
    assert_exit_code 1 $? "is_valid_url: ftp:// scheme should be invalid"

    # Test Path Sanitization
    clean_path=$(sanitize_path "../../../etc/passwd")
    assert_equals "etc/passwd" "$clean_path" "sanitize_path should strip relative directory traversal"
else
    log_fail "modules/validation.sh missing"
fi
echo ""

# -------------------------------------------------------------------
# TEST SUITE 3: SUBDOMAIN FINDER MODULE
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 3: Subdomain Finder Module Integration Tests${NC}"

# Test invalid domain rejection
bash modules/subdomain_finder.sh "invalid_domain_format" all &>/dev/null
assert_exit_code 1 $? "subdomain_finder: Rejects invalid domain format"

# Test missing parameters
bash modules/subdomain_finder.sh &>/dev/null
assert_exit_code 1 $? "subdomain_finder: Rejects missing arguments"

# Test OSINT scan types
bash modules/subdomain_finder.sh "example.com" osint &>/dev/null
assert_exit_code 0 $? "subdomain_finder: Aggregated Passive OSINT scan mode succeeded"

bash modules/subdomain_finder.sh "example.com" hackertarget &>/dev/null
assert_exit_code 0 $? "subdomain_finder: HackerTarget OSINT scan mode succeeded"

echo ""

# -------------------------------------------------------------------
# TEST SUITE 4: SUBDOMAIN CLEANER MODULE
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 4: Subdomain Cleaner Integration Tests${NC}"

# Create mock subdomain discovery output directory
MOCK_DIR="output/test_mock_subdomains_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$MOCK_DIR"

cat <<'EOF' > "$MOCK_DIR/common_subdomains_test.txt"
[OK] FOUND: www.example.com
[OK] FOUND: api.example.com
[OK] FOUND: mail.example.com
EOF

cat <<'EOF' > "$MOCK_DIR/dns_enum_test.txt"
test.example.com
admin.example.com
EOF

# Run extraction test
bash modules/subdomain_cleaner.sh "$MOCK_DIR" extract &>/dev/null
assert_exit_code 0 $? "subdomain_cleaner: extract action succeeded"

# Run JSON export test
bash modules/subdomain_cleaner.sh "$MOCK_DIR" json &>/dev/null
assert_exit_code 0 $? "subdomain_cleaner: json export action succeeded"

# Run CSV export test
bash modules/subdomain_cleaner.sh "$MOCK_DIR" csv &>/dev/null
assert_exit_code 0 $? "subdomain_cleaner: csv export action succeeded"

# Clean up mock directory
rm -rf "$MOCK_DIR"

echo ""

# -------------------------------------------------------------------
# TEST SUITE 5: WEB VULNERABILITIES MODULE
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 5: Web Vulnerabilities Module Integration Tests${NC}"

# Test invalid URL rejection
bash modules/web_vulnerabilities.sh "not_a_valid_url" 1 &>/dev/null
assert_exit_code 1 $? "web_vulnerabilities: Rejects invalid URL format"

# Test non-interactive execution with valid URL
bash modules/web_vulnerabilities.sh "http://127.0.0.1" 1 &>/dev/null
assert_exit_code 0 $? "web_vulnerabilities: Runs SQLi scan in non-interactive mode"

echo ""

# -------------------------------------------------------------------
# TEST SUITE 7: PASSIVE OSINT MODULE
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 7: Passive OSINT Module Integration Tests${NC}"

bash modules/passive.sh "example.com" &>/dev/null
assert_exit_code 0 $? "passive.sh: Runs passive OSINT collection for a valid domain"

passive_json=$(ls output/passive_example.com_*.json 2>/dev/null | head -n 1)
if [[ -n "$passive_json" && -f "$passive_json" ]]; then
    log_pass "passive.sh: JSON output file created at $passive_json"
else
    log_fail "passive.sh: Expected JSON output file was not created"
fi

echo ""

# -------------------------------------------------------------------
# TEST SUITE 8: MULTI-TARGET BATCH SCANNER MODULE
# -------------------------------------------------------------------
echo -e "${YELLOW}-> TEST SUITE 8: Multi-Target Batch Scanner Integration Tests${NC}"

# Create mock targets file
MOCK_TARGETS_FILE="output/test_mock_targets.txt"
cat <<'EOF' > "$MOCK_TARGETS_FILE"
# Sample Test Targets File
127.0.0.1
example.com
http://127.0.0.1
EOF

# Test batch runner execution
bash modules/batch_runner.sh "$MOCK_TARGETS_FILE" recon 2 &>/dev/null
assert_exit_code 0 $? "batch_runner: Executed multi-target batch scan successfully"

# Test missing file error code
bash modules/batch_runner.sh "non_existent_file.txt" recon &>/dev/null
assert_exit_code 1 $? "batch_runner: Rejects non-existent targets file"

rm -f "$MOCK_TARGETS_FILE"

echo ""

# -------------------------------------------------------------------
# SUMMARY REPORT
# -------------------------------------------------------------------
TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS + SKIPPED_TESTS))
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}                   TEST SUMMARY                     ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "Total Tests Run : $TOTAL_TESTS"
echo -e "Passed          : ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed          : ${RED}$FAILED_TESTS${NC}"
echo -e "Skipped         : ${YELLOW}$SKIPPED_TESTS${NC}"
echo -e "${BLUE}====================================================${NC}\n"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}[PASS] ALL TESTS PASSED SUCCESSFULLY!${NC}"
    exit 0
else
    echo -e "${RED}[ERROR] SOME TESTS FAILED. PLEASE REVIEW LOGS ABOVE.${NC}"
    exit 1
fi
