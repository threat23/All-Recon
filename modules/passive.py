#!/usr/bin/env python3

import asyncio
import json
import re
import sys
import time
from urllib.parse import quote

try:
    import aiohttp
except ImportError as exc:  # pragma: no cover - dependency installation path
    print(
        f"Missing dependency: {exc}. Install with: python3 -m pip install -r requirements.txt",
        file=sys.stderr,
    )
    raise SystemExit(1)


TARGET_RE = re.compile(r"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$")
IP_RE = re.compile(r"^(?:\d{1,3}\.){3}\d{1,3}$")


def is_domain(value: str) -> bool:
    return bool(TARGET_RE.match(value.strip().lower()))


def is_ip(value: str) -> bool:
    if not IP_RE.match(value.strip()):
        return False
    parts = value.split(".")
    return all(0 <= int(p) <= 255 for p in parts)


def sanitize_target(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9.-]", "_", value.strip()) or "target"


async def fetch_json(session: aiohttp.ClientSession, url: str, timeout: int = 12):
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=timeout)) as response:
            text = await response.text()
            if not text:
                return {"ok": response.status < 400, "status": response.status, "data": None}
            try:
                data = json.loads(text)
                return {"ok": response.status < 400, "status": response.status, "data": data}
            except json.JSONDecodeError:
                return {"ok": response.status < 400, "status": response.status, "raw": text[:2000]}
    except Exception as exc:  # pragma: no cover - network failure handled gracefully
        return {"ok": False, "status": None, "error": str(exc)}


def unique_values(values):
    result = []
    seen = set()
    for item in values:
        cleaned = str(item).strip()
        if not cleaned or cleaned in seen:
            continue
        seen.add(cleaned)
        result.append(cleaned)
    return result


async def collect_crtsh(session: aiohttp.ClientSession, target: str):
    candidates = [f"%25.{target}", target]
    records = []
    for candidate in candidates:
        url = f"https://crt.sh/?q={quote(candidate)}&output=json"
        response = await fetch_json(session, url)
        if not response.get("ok", False) or response.get("data") is None:
            continue
        data = response["data"]
        if not isinstance(data, list):
            continue
        for item in data:
            if not isinstance(item, dict):
                continue
            raw_names = item.get("name_value") or ""
            for name in str(raw_names).splitlines():
                clean = name.strip()
                if not clean:
                    continue
                if target in clean or clean.endswith("." + target) or clean == target:
                    records.append(clean)
            if item.get("common_name"):
                records.append(str(item.get("common_name")).strip())
            if item.get("issuer_name"):
                records.append(str(item.get("issuer_name")).strip())
        if records:
            break
    return {"status": "ok" if records else "no_results", "count": len(unique_values(records)), "results": unique_values(records)}


async def collect_wayback(session: aiohttp.ClientSession, target: str):
    url = f"https://web.archive.org/cdx/search/cdx?url={quote(target)}/*&output=json&fl=original&collapse=urlkey&limit=25"
    response = await fetch_json(session, url)
    data = response.get("data")
    if not isinstance(data, list):
        return {"status": "no_results", "count": 0, "results": []}
    results = []
    for row in data[1:]:
        if not isinstance(row, list) or not row:
            continue
        entry = str(row[0]).strip()
        if entry:
            results.append(entry)
    unique = unique_values(results)
    return {"status": "ok" if unique else "no_results", "count": len(unique), "results": unique[:25]}


def compact_rdap(data):
    if not isinstance(data, dict):
        return {"status": "no_results", "record": {}}
    record = {}
    for key in ("handle", "ldhName", "ipVersion", "startAddress", "endAddress", "remarks", "port43", "objectClassName"):
        if key in data:
            record[key] = data[key]
    if "entities" in data:
        record["entities"] = data["entities"][:5]
    if "nameserver" in data:
        record["nameservers"] = data["nameserver"]
    if "nameservers" in data:
        record["nameservers"] = data["nameservers"]
    return {"status": "ok", "record": record}


async def collect_rdap(session: aiohttp.ClientSession, target: str):
    if is_ip(target):
        url = f"https://rdap.org/ip/{target}"
    elif is_domain(target):
        url = f"https://rdap.org/domain/{target}"
    else:
        return {"status": "invalid_target", "message": "Target is not a valid IP or domain", "record": {}}

    response = await fetch_json(session, url)
    if not response.get("ok", False):
        return {"status": "error", "message": response.get("error", "RDAP query failed"), "record": {}}
    data = response.get("data")
    if not isinstance(data, dict):
        return {"status": "no_results", "message": "RDAP returned no data", "record": {}}
    return compact_rdap(data)


async def collect_shodan_placeholder():
    return {
        "status": "placeholder",
        "message": "Shodan API integration is not enabled in this build.",
        "results": [],
    }


async def run_target(target: str):
    target = target.strip()
    if not target:
        raise ValueError("No target supplied")
    if not (is_domain(target) or is_ip(target)):
        raise ValueError(f"Invalid target format: '{target}'")

    async with aiohttp.ClientSession() as session:
        crtsh_task = collect_crtsh(session, target)
        wayback_task = collect_wayback(session, target)
        rdap_task = collect_rdap(session, target)
        shodan_task = collect_shodan_placeholder()
        crtsh, wayback, rdap, shodan = await asyncio.gather(crtsh_task, wayback_task, rdap_task, shodan_task)

    result = {
        "target": target,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "crt_sh": crtsh,
        "wayback": wayback,
        "rdap": rdap,
        "shodan": shodan,
    }
    return result


def main(argv):
    if len(argv) < 2:
        print(f"Usage: {argv[0]} <target> [output.json]", file=sys.stderr)
        return 1

    target = argv[1]
    output_path = argv[2] if len(argv) > 2 else None

    try:
        result = asyncio.run(run_target(target))
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # pragma: no cover - unexpected runtime failure
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    json_output = json.dumps(result, indent=2, sort_keys=True)
    if output_path:
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(json_output)
            handle.write("\n")
    else:
        print(json_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
