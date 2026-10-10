#!/usr/bin/env python3
"""DNS, DNSSEC, and email-domain posture audit using the system dig utility.

No email is sent and no authentication is attempted. DKIM is checked only
against a small common-selector list; no result is not proof DKIM is absent.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$")
DKIM_SELECTORS = ("default", "selector1", "selector2", "google", "k1", "mail", "dkim", "s1", "s2", "mandrill")


def normalize_domain(value):
    value = value.strip().rstrip(".")
    if "://" in value:
        from urllib.parse import urlsplit
        value = urlsplit(value).hostname or ""
    else:
        value = value.split("/", 1)[0]
    try:
        value = value.encode("idna").decode("ascii").lower()
    except UnicodeError as exc:
        raise ValueError("Target must be a valid domain.") from exc
    if not DOMAIN_RE.fullmatch(value):
        raise ValueError("Target must be a domain name (not an IP address or URL path).")
    return value


def dig(name, record_type):
    try:
        proc = subprocess.run(
            ["dig", "+time=2", "+tries=1", "+dnssec", "+noall", "+answer", name, record_type],
            capture_output=True, text=True, timeout=4, check=False,
        )
    except subprocess.TimeoutExpired:
        return {"records": [], "error": "dig timed out"}
    except OSError as exc:
        return {"records": [], "error": str(exc)}
    if proc.returncode != 0:
        return {"records": [], "error": (proc.stderr.strip() or f"dig exited {proc.returncode}")}
    records = []
    for line in proc.stdout.splitlines():
        fields = line.split(None, 4)
        if len(fields) >= 5:
            records.append({"owner": fields[0].rstrip("."), "ttl": fields[1], "type": fields[3], "value": fields[4].strip()})
    return {"records": records, "error": None}


def values(result):
    return [row["value"] for row in result.get("records", [])]


def txt_value(value):
    return value.replace('"', "").strip()


def assess(domain, raw):
    findings = []
    def add(severity, title, evidence, recommendation):
        findings.append({"severity": severity, "title": title, "evidence": evidence, "recommendation": recommendation})

    txt_records = [txt_value(v) for v in values(raw["txt"])]
    spf = [record for record in txt_records if record.lower().startswith("v=spf1")]
    if not spf:
        add("medium", "No SPF policy observed", "No TXT record beginning v=spf1 was returned for the domain.", "Publish a single SPF record covering legitimate senders and finish with an intentional qualifier.")
    elif len(spf) > 1:
        add("high", "Multiple SPF records", f"{len(spf)} SPF TXT records were returned; receivers commonly treat this as a permerror.", "Consolidate senders into one SPF record.")
    else:
        policy = spf[0].lower()
        if re.search(r"(?:^|\s)\+all(?:\s|$)", policy):
            add("high", "SPF permits any sender", spf[0], "Replace +all with an appropriate restrictive qualifier and validate legitimate sending sources.")
        elif re.search(r"(?:^|\s)\?all(?:\s|$)", policy):
            add("medium", "SPF policy is neutral", spf[0], "Review whether a restrictive SPF ending is appropriate for this domain.")
        elif re.search(r"(?:^|\s)~all(?:\s|$)", policy):
            add("low", "SPF uses softfail", spf[0], "Confirm the sender inventory and consider -all when all legitimate senders are accounted for.")
        elif re.search(r"(?:^|\s)-all(?:\s|$)", policy):
            add("info", "SPF has hard-fail qualifier", spf[0], "Periodically verify that all legitimate senders remain covered.")
        else:
            add("low", "SPF ending not recognized", spf[0], "Check that the SPF policy ends with an intentional qualifier.")

    dmarc = [txt_value(v) for v in values(raw["dmarc"]) if txt_value(v).lower().startswith("v=dmarc1")]
    if not dmarc:
        add("medium", "DMARC record not observed", "No v=DMARC1 record was returned at _dmarc." + domain, "Publish a DMARC policy and review aggregate reports before moving from monitoring to enforcement.")
    else:
        policy_match = re.search(r"(?:^|;)\s*p\s*=\s*([a-z]+)", dmarc[0], re.I)
        policy = policy_match.group(1).lower() if policy_match else "unspecified"
        if policy == "none":
            add("low", "DMARC is monitoring-only", dmarc[0], "Review aggregate reports and consider quarantine/reject after legitimate email flows are aligned.")
        elif policy not in ("quarantine", "reject"):
            add("medium", "DMARC policy needs review", dmarc[0], "Set an explicit DMARC policy after validating sending infrastructure.")
        else:
            add("info", "DMARC enforcement policy observed", f"p={policy}", "Confirm alignment and report delivery remain correct.")
        pct_match = re.search(r"(?:^|;)\s*pct\s*=\s*(\d+)", dmarc[0], re.I)
        if pct_match and int(pct_match.group(1)) < 100:
            add("low", "DMARC enforcement is sampled", f"pct={pct_match.group(1)}", "Consider increasing pct after monitoring confirms legitimate mail passes.")
        if not re.search(r"(?:^|;)\s*rua\s*=", dmarc[0], re.I):
            add("info", "DMARC aggregate reports not configured", dmarc[0], "Consider an appropriate rua destination to improve visibility.")

    if not values(raw["mx"]):
        add("info", "No MX records observed", "The domain returned no MX records.", "Confirm whether this domain is intended to receive email; absence may be expected.")
    if not values(raw["caa"]):
        add("info", "No CAA records observed", "The domain returned no CAA records.", "Consider CAA records to define which certificate authorities may issue certificates for this domain.")
    dnskey_rows = raw["dnskey"].get("records", [])
    has_dnskey = any(row["type"] == "DNSKEY" for row in dnskey_rows)
    has_rrsig = any(row["type"] == "RRSIG" for row in dnskey_rows)
    if has_dnskey and has_rrsig:
        add("info", "DNSSEC signatures observed", "DNSKEY and RRSIG records were returned for the zone.", "Ensure the registrar/parent DS chain is valid; this lightweight check does not validate the full chain.")
    else:
        add("low", "DNSSEC signing not confirmed", "No DNSKEY plus RRSIG pair was observed in the response.", "Verify DNSSEC status with a validating resolver and confirm the parent DS record if signing is expected.")

    if not values(raw["mta_sts"]):
        add("low", "MTA-STS policy discovery record not observed", "No TXT record was returned at _mta-sts." + domain, "If the domain receives mail, consider deploying MTA-STS and publishing its HTTPS policy.")
    if not values(raw["tls_rpt"]):
        add("info", "SMTP TLS reporting record not observed", "No TXT record was returned at _smtp._tls." + domain, "Consider TLS-RPT to receive reports on SMTP TLS delivery issues.")
    found_dkim = [selector for selector, result in raw["dkim"].items() if result.get("records")]
    if found_dkim:
        add("info", "Common DKIM selector(s) observed", ", ".join(found_dkim), "Confirm selectors correspond to active authorized mail providers and rotate retired keys.")
    else:
        add("info", "No tested DKIM selectors observed", "No records were found for the limited common-selector list; this is not proof DKIM is absent.", "Check provider documentation and the domain's actual DKIM selectors.")

    return findings


def collect(domain):
    record_names = {
        "a": (domain, "A"),
        "aaaa": (domain, "AAAA"),
        "ns": (domain, "NS"),
        "soa": (domain, "SOA"),
        "mx": (domain, "MX"),
        "txt": (domain, "TXT"),
        "caa": (domain, "CAA"),
        "dnskey": (domain, "DNSKEY"),
        "dmarc": (f"_dmarc.{domain}", "TXT"),
        "mta_sts": (f"_mta-sts.{domain}", "TXT"),
        "tls_rpt": (f"_smtp._tls.{domain}", "TXT"),
    }
    raw = {key: dig(name, record_type) for key, (name, record_type) in record_names.items()}
    raw["dkim"] = {
        selector: dig(f"{selector}._domainkey.{domain}", "TXT")
        for selector in DKIM_SELECTORS
    }
    result = {
        "target": domain,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "method": "DNS queries via dig with DNSSEC records requested",
        "records": raw,
        "findings": assess(domain, raw),
        "scope_note": "Read-only DNS lookups only. No mail was sent. DKIM checks use a limited common-selector list; DNSSEC status is a heuristic, not full chain validation.",
    }
    return result


def main():
    parser = argparse.ArgumentParser(description="Audit public DNS and email authentication posture for a domain.")
    parser.add_argument("target", help="Domain to audit")
    parser.add_argument("--output-dir", default="output", help="Directory for reports (default: output)")
    args = parser.parse_args()
    if shutil.which("dig") is None:
        print("[!] The 'dig' utility is required. Install dnsutils (Debian/Kali: sudo apt install dnsutils).", file=sys.stderr)
        return 2
    try:
        domain = normalize_domain(args.target)
    except ValueError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 2
    data = collect(domain)
    os.makedirs(args.output_dir, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9.-]", "_", domain)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(args.output_dir, f"dns_email_audit_{safe}_{stamp}.json")
    text_path = os.path.join(args.output_dir, f"dns_email_audit_{safe}_{stamp}.txt")
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)

    lines = [
        "ALL-RECON — DNS / EMAIL SECURITY AUDIT",
        f"Target: {domain}",
        f"Generated: {data['generated_at']}",
        "",
        "DNS record inventory:",
    ]
    display_keys = ("a", "aaaa", "ns", "soa", "mx", "txt", "caa", "dnskey", "dmarc", "mta_sts", "tls_rpt")
    for key in display_keys:
        label = key.upper().replace("_", "-")
        recs = values(data["records"][key])
        lines.append(f"  {label}:")
        lines.extend([f"    {record}" for record in recs] or ["    (no answer observed)"])
    lines.append("  DKIM common selectors with answers: " + (", ".join(selector for selector, rec in data["records"]["dkim"].items() if rec.get("records")) or "none observed"))
    lines.extend(["", "Findings (review in context):"])
    for finding in data["findings"]:
        lines.append(f"  [{finding['severity'].upper()}] {finding['title']}")
        lines.append(f"    Evidence: {finding['evidence']}")
        lines.append(f"    Recommendation: {finding['recommendation']}")
    errors = []
    for key, record in data["records"].items():
        if key == "dkim":
            errors.extend(f"{selector}: {entry['error']}" for selector, entry in record.items() if entry.get("error"))
        elif record.get("error"):
            errors.append(f"{key}: {record['error']}")
    if errors:
        lines.extend(["", "Lookup errors:"] + [f"  - {error}" for error in errors])
    lines.extend(["", data["scope_note"], f"JSON: {json_path}"])
    report = "\n".join(lines) + "\n"
    with open(text_path, "w", encoding="utf-8") as handle:
        handle.write(report)
    print(report, end="")
    print(f"Text report: {text_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
