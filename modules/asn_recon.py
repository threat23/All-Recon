#!/usr/bin/env python3
"""Passive ASN/IP ownership and announced-prefix enrichment via RIPEstat.

This module resolves a supplied domain locally, then queries public RIPEstat
endpoints for routing/registration context. It does not scan ports or probe
the returned address ranges.
"""
import argparse
import ipaddress
import json
import os
import re
import socket
import sys
import time
from datetime import datetime, timezone
from urllib.error import URLError, HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$")
USER_AGENT = "ALL-RECON/1.0 (authorized security assessment; passive enrichment)"


def normalize_target(value):
    value = value.strip()
    if "://" in value:
        value = urlsplit(value).hostname or ""
    else:
        value = value.split("/", 1)[0].split(":", 1)[0]
    if not value:
        raise ValueError("Target is empty.")
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        pass
    value = value.rstrip(".").lower()
    try:
        value = value.encode("idna").decode("ascii")
    except UnicodeError as exc:
        raise ValueError("Target is not a valid domain or IP address.") from exc
    if not DOMAIN_RE.fullmatch(value):
        raise ValueError("Target must be a valid domain or IP address.")
    return value


def fetch_json(url, timeout=12):
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as response:
            if response.status < 200 or response.status >= 300:
                return None, f"HTTP {response.status}"
            return json.loads(response.read(3_000_000).decode("utf-8")), None
    except (URLError, HTTPError, TimeoutError, OSError, ValueError, json.JSONDecodeError) as exc:
        return None, str(exc)


def resolve_target(target):
    try:
        return [str(ipaddress.ip_address(target))]
    except ValueError:
        pass
    addresses = set()
    try:
        for item in socket.getaddrinfo(target, None, type=socket.SOCK_STREAM):
            addresses.add(item[4][0].split("%", 1)[0])
    except socket.gaierror as exc:
        raise RuntimeError(f"Could not resolve {target}: {exc}") from exc
    ordered = sorted(addresses, key=lambda item: (ipaddress.ip_address(item).version, int(ipaddress.ip_address(item))))
    return ordered[:20]


def ripe_data(endpoint, resource):
    url = f"https://stat.ripe.net/data/{endpoint}/data.json?resource={quote(str(resource), safe='')}"
    payload, error = fetch_json(url)
    if error:
        return None, error
    if not isinstance(payload, dict) or payload.get("status") not in (None, "ok"):
        return None, str(payload.get("status", "Unexpected RIPEstat response"))
    return payload.get("data") or {}, None


def collect(target):
    started = datetime.now(timezone.utc).isoformat()
    addresses = resolve_target(target)
    result = {
        "target": target,
        "generated_at": started,
        "source": "RIPEstat public API",
        "resolved_addresses": addresses,
        "address_details": [],
        "as_details": [],
        "errors": [],
        "scope_note": "Public routing/registration enrichment only; no probes of returned prefixes were run.",
    }
    asns = set()
    for address in addresses:
        data, error = ripe_data("network-info", address)
        row = {"ip": address, "prefix": None, "asns": [], "error": error}
        if data:
            row["prefix"] = data.get("prefix")
            row["asns"] = data.get("asns") or []
            for asn in row["asns"]:
                try:
                    asns.add(int(asn))
                except (ValueError, TypeError):
                    continue
        elif error:
            result["errors"].append(f"network-info {address}: {error}")
        result["address_details"].append(row)

    for asn in sorted(asns):
        overview, overview_error = ripe_data("as-overview", f"AS{asn}")
        prefixes_data, prefixes_error = ripe_data("announced-prefixes", f"AS{asn}")
        prefixes = []
        if prefixes_data and isinstance(prefixes_data.get("prefixes"), list):
            prefixes = [
                item.get("prefix")
                for item in prefixes_data["prefixes"]
                if isinstance(item, dict) and item.get("prefix")
            ]
        item = {
            "asn": asn,
            "holder": (overview or {}).get("holder"),
            "country": (overview or {}).get("country"),
            "type": (overview or {}).get("type"),
            "announced": (overview or {}).get("announced"),
            "announced_prefix_count_returned": len(prefixes),
            "announced_prefixes_sample": prefixes[:50],
        }
        if overview_error:
            item["overview_error"] = overview_error
            result["errors"].append(f"AS{asn} overview: {overview_error}")
        if prefixes_error:
            item["prefixes_error"] = prefixes_error
            result["errors"].append(f"AS{asn} prefixes: {prefixes_error}")
        result["as_details"].append(item)

    return result


def main():
    parser = argparse.ArgumentParser(description="Map a domain/IP to public ASN and announced-prefix context.")
    parser.add_argument("target", help="Domain, IP, or URL whose host should be mapped")
    parser.add_argument("--output-dir", default="output", help="Directory for JSON and text reports (default: output)")
    args = parser.parse_args()
    try:
        target = normalize_target(args.target)
        data = collect(target)
    except (ValueError, RuntimeError) as exc:
        print(f"[!] {exc}", file=sys.stderr)
        return 2

    os.makedirs(args.output_dir, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9.-]", "_", target)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    json_path = os.path.join(args.output_dir, f"asn_{safe}_{stamp}.json")
    text_path = os.path.join(args.output_dir, f"asn_{safe}_{stamp}.txt")
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)

    lines = [
        "ALL-RECON — ASN / IP MAPPING",
        f"Target: {target}",
        f"Generated: {data['generated_at']}",
        "",
        "Resolved addresses and routing prefixes:",
    ]
    if not data["address_details"]:
        lines.append("  No addresses resolved.")
    for row in data["address_details"]:
        lines.append(f"  {row['ip']}  prefix={row.get('prefix') or 'unknown'}  ASN(s)={row.get('asns') or 'unknown'}")
    lines.extend(["", "ASN details:"])
    if not data["as_details"]:
        lines.append("  No ASN details returned.")
    for item in data["as_details"]:
        lines.append(f"  AS{item['asn']} — {item.get('holder') or 'holder unknown'}")
        lines.append(f"    Country: {item.get('country') or 'unknown'} | Type: {item.get('type') or 'unknown'}")
        lines.append(f"    Announced: {item.get('announced')}")
        lines.append(f"    Prefixes returned: {item['announced_prefix_count_returned']}; sample: {', '.join(item['announced_prefixes_sample'][:10]) or 'none'}")
    if data["errors"]:
        lines.extend(["", "Warnings / API errors:"] + [f"  - {error}" for error in data["errors"]])
    lines.extend(["", data["scope_note"], f"JSON: {json_path}"])
    report = "\n".join(lines) + "\n"
    with open(text_path, "w", encoding="utf-8") as handle:
        handle.write(report)
    print(report, end="")
    print(f"Text report: {text_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
