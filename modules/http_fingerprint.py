#!/usr/bin/env python3
"""Low-impact HTTP/TLS fingerprinting for explicitly supplied authorized URLs."""
import argparse
import html
import json
import os
import re
import socket
import ssl
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

USER_AGENT = "ALL-RECON/1.0 (authorized security assessment; HTTP fingerprint)"
MAX_BODY = 1_000_000


class NoRedirect(HTTPRedirectHandler):
    """Record redirects without automatically probing a second host."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def normalize_url(value):
    value = value.strip()
    if not value:
        raise ValueError("Target URL is empty.")
    if "://" not in value:
        value = "https://" + value
    parsed = urlsplit(value)
    if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
        raise ValueError("Target must be an http:// or https:// URL or a domain name.")
    if parsed.username or parsed.password:
        raise ValueError("Do not embed credentials in the target URL.")
    if any(ch in parsed.hostname for ch in "\r\n\t"):
        raise ValueError("Invalid hostname.")
    return value


def flatten_name(entries):
    parts = []
    for group in entries or ():
        for key, value in group:
            parts.append(f"{key}={value}")
    return ", ".join(parts) or None


def tls_fingerprint(host, port, timeout):
    result = {"checked": True, "valid": False, "issuer": None, "subject": None, "not_before": None, "not_after": None, "error": None}
    try:
        context = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=timeout) as raw:
            with context.wrap_socket(raw, server_hostname=host) as sock:
                cert = sock.getpeercert()
                result["valid"] = True
                result["issuer"] = flatten_name(cert.get("issuer"))
                result["subject"] = flatten_name(cert.get("subject"))
                result["not_before"] = cert.get("notBefore")
                result["not_after"] = cert.get("notAfter")
                if cert.get("notAfter"):
                    remaining = ssl.cert_time_to_seconds(cert["notAfter"]) - time.time()
                    result["days_until_expiry"] = int(remaining // 86400)
    except (OSError, ssl.SSLError, ValueError) as exc:
        result["error"] = str(exc)
    return result


def detect_technologies(headers, body):
    clues = []
    lower = body.lower()
    header_text = " ".join(f"{k}: {v}" for k, v in headers.items()).lower()
    signatures = [
        ("WordPress", r"wp-content/|wp-includes/|wordpress"),
        ("Drupal", r"drupal-settings-json|/sites/default/files/|drupal"),
        ("Joomla", r"/media/system/js/|content=\"joomla"),
        ("Next.js", r"__next_data__|/_next/static/"),
        ("Nuxt", r"__nuxt__|/_nuxt/"),
        ("React", r"react(?:\.development|\.production)?\.js|data-reactroot|__react"),
        ("Vue.js", r"vue(?:\.runtime)?\.global|data-v-[0-9a-f]+"),
        ("Angular", r"ng-version=|angular\.js"),
        ("Shopify", r"cdn\.shopify\.com|shopify"),
    ]
    for name, pattern in signatures:
        if re.search(pattern, lower, re.I):
            clues.append(name)
    if "x-powered-by" in header_text:
        clues.append("X-Powered-By header present")
    if "server" in header_text:
        clues.append("Server header present")
    return sorted(set(clues))


def collect(url, timeout):
    parsed = urlsplit(url)
    host = parsed.hostname
    port = parsed.port or (443 if parsed.scheme.lower() == "https" else 80)
    request = Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.5",
        "Connection": "close",
    }, method="GET")
    opener = build_opener(NoRedirect())
    status, reason, response_headers, final_body, error = None, None, {}, b"", None
    try:
        response = opener.open(request, timeout=timeout)
    except HTTPError as exc:
        response = exc
    except (URLError, TimeoutError, OSError, ValueError) as exc:
        response = None
        error = str(exc)

    if response is not None:
        try:
            status = getattr(response, "status", None) or getattr(response, "code", None)
            reason = getattr(response, "reason", None)
            hdrs = response.headers
            response_headers = {key.lower(): value.strip() for key, value in hdrs.items()}
            try:
                final_body = response.read(MAX_BODY)
            except (OSError, ValueError):
                final_body = b""
        finally:
            response.close()

    charset = "utf-8"
    content_type = response_headers.get("content-type", "")
    match = re.search(r"charset=([A-Za-z0-9._-]+)", content_type, re.I)
    if match:
        charset = match.group(1)
    body = final_body.decode(charset, errors="replace")
    title_match = re.search(r"<title\b[^>]*>(.*?)</title\s*>", body, re.I | re.S)
    title = html.unescape(re.sub(r"\s+", " ", title_match.group(1))).strip() if title_match else None

    set_cookie = []
    if response is not None:
        try:
            set_cookie = response.headers.get_all("Set-Cookie") or []
        except (AttributeError, TypeError):
            pass
    cookie_findings = []
    for cookie in set_cookie:
        flags = cookie.lower()
        missing = []
        if "secure" not in flags:
            missing.append("Secure")
        if "httponly" not in flags:
            missing.append("HttpOnly")
        if "samesite" not in flags:
            missing.append("SameSite")
        if missing:
            cookie_findings.append({"cookie_name": cookie.split("=", 1)[0].strip(), "missing_flags": missing})

    security_headers = {
        "strict-transport-security": "HSTS",
        "content-security-policy": "Content-Security-Policy",
        "x-content-type-options": "X-Content-Type-Options",
        "x-frame-options": "X-Frame-Options",
        "referrer-policy": "Referrer-Policy",
        "permissions-policy": "Permissions-Policy",
    }
    missing_headers = [
        label for header, label in security_headers.items()
        if header not in response_headers and not (header == "strict-transport-security" and parsed.scheme.lower() != "https")
    ]
    tls = tls_fingerprint(host, port, timeout) if parsed.scheme.lower() == "https" else {"checked": False, "valid": False, "error": "Target URL is HTTP; TLS was not tested."}
    safe_headers = {
        key: response_headers[key] for key in (
            "server", "x-powered-by", "via", "location", "content-type",
            "content-length", "cache-control", "x-cache", "cf-ray",
            "x-served-by", "x-amz-cf-id", "x-runtime",
        ) if key in response_headers
    }
    return {
        "target_url": url,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "http": {
            "status": status, "reason": str(reason) if reason is not None else None,
            "observed_headers": safe_headers,
            "missing_security_headers": missing_headers,
            "title": title,
            "bytes_read_capped_at": MAX_BODY,
            "body_read_bytes": len(final_body),
            "technology_clues": detect_technologies(response_headers, body),
            "cookie_flag_findings": cookie_findings,
            "redirect_not_followed": bool(status and status in (301, 302, 303, 307, 308)),
            "error": error,
        },
        "tls": tls,
        "scope_note": "Only the supplied URL was requested; redirects are recorded but not followed. Body reads are capped at 1 MB.",
    }


def main():
    parser = argparse.ArgumentParser(description="Fingerprint HTTP headers, page clues, cookies, and TLS on one authorized URL.")
    parser.add_argument("target", help="Authorized URL or domain name (domain-only input defaults to HTTPS)")
    parser.add_argument("--timeout", type=float, default=8.0, help="Network timeout in seconds (default: 8)")
    parser.add_argument("--output-dir", default="output", help="Directory for reports (default: output)")
    args = parser.parse_args()
    if args.timeout <= 0 or args.timeout > 60:
        parser.error("--timeout must be greater than 0 and no more than 60 seconds")
    try:
        url = normalize_url(args.target)
        data = collect(url, args.timeout)
    except ValueError as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 2

    os.makedirs(args.output_dir, exist_ok=True)
    host = urlsplit(url).hostname or "target"
    safe = re.sub(r"[^A-Za-z0-9.-]", "_", host)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(args.output_dir, f"http_fingerprint_{safe}_{stamp}.json")
    text_path = os.path.join(args.output_dir, f"http_fingerprint_{safe}_{stamp}.txt")
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)

    http_data = data["http"]
    lines = [
        "ALL-RECON — HTTP / TLS FINGERPRINT",
        f"Target: {url}",
        f"Generated: {data['generated_at']}",
        f"HTTP status: {http_data['status'] or 'unavailable'} {http_data['reason'] or ''}".rstrip(),
        f"Page title: {http_data['title'] or 'not detected'}",
        f"Technology clues: {', '.join(http_data['technology_clues']) or 'none detected'}",
        "",
        "Selected response headers:",
    ]
    lines.extend([f"  {key}: {value}" for key, value in http_data["observed_headers"].items()] or ["  none captured"])
    lines.extend(["", "Missing security headers (review in context):"])
    lines.extend([f"  - {item}" for item in http_data["missing_security_headers"]] or ["  none among the checked headers"])
    lines.extend(["", "Cookie flags:"])
    lines.extend([f"  {item['cookie_name']}: missing {', '.join(item['missing_flags'])}" for item in http_data["cookie_flag_findings"]] or ["  no cookie flag issue observed (or no cookies set)"])
    tls = data["tls"]
    lines.extend(["", "TLS certificate:"])
    if tls.get("checked"):
        lines.append(f"  Validated: {tls.get('valid')}")
        lines.append(f"  Subject: {tls.get('subject') or 'unavailable'}")
        lines.append(f"  Issuer: {tls.get('issuer') or 'unavailable'}")
        lines.append(f"  Expires: {tls.get('not_after') or 'unavailable'}")
        if tls.get("days_until_expiry") is not None:
            lines.append(f"  Days until expiry: {tls['days_until_expiry']}")
        if tls.get("error"):
            lines.append(f"  Error: {tls['error']}")
    else:
        lines.append(f"  {tls.get('error')}")
    if http_data.get("error"):
        lines.extend(["", f"HTTP request error: {http_data['error']}"])
    lines.extend(["", data["scope_note"], f"JSON: {json_path}"])
    report = "\n".join(lines) + "\n"
    with open(text_path, "w", encoding="utf-8") as handle:
        handle.write(report)
    print(report, end="")
    print(f"Text report: {text_path}")
    return 0 if http_data["status"] is not None else 1


if __name__ == "__main__":
    raise SystemExit(main())
