#!/usr/bin/env python3
"""Async passive footprinting module for ALL-RECON.

Returns JSON-ready dictionaries and can be called directly from
`modules/passive.sh` or imported as `PassiveCollector.collect(domain)`.

Example:
    python3 modules/passive.py example.com --sources crtsh,wayback,rdap
"""

import argparse
import asyncio
import hashlib
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

import aiohttp

DEFAULT_CACHE_DIR = os.environ.get("ALLRECON_CACHE_DIR", ".allrecon_cache")
DEFAULT_TIMEOUT = 20
DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}


def _ensure_cache_dir() -> str:
    cache_dir = os.environ.get("ALLRECON_CACHE_DIR", DEFAULT_CACHE_DIR)
    os.makedirs(cache_dir, exist_ok=True)
    return cache_dir


def cache_key(name: str, target: str) -> str:
    h = hashlib.sha1(f"{name}|{target}".encode()).hexdigest()
    return os.path.join(_ensure_cache_dir(), f"{name}_{h}.json")


def normalize_target(target: str) -> str:
    """Strip scheme/path from a URL and return a bare domain or IP."""
    t = target.strip().lower()
    t = t.replace("http://", "").replace("https://", "")
    t = t.split("/")[0].split(":")[0]
    return t


async def fetch_json(
    session: aiohttp.ClientSession,
    url: str,
    params: Optional[Dict[str, Any]] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> Optional[Any]:
    try:
        async with session.get(
            url, params=params, headers=headers, timeout=timeout
        ) as resp:
            text = await resp.text()
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return {"status": resp.status, "text": text[:500]}
    except Exception as exc:  # pragma: no cover - network resilience
        return {"error": str(exc)}


async def crtsh_search(
    session: aiohttp.ClientSession, domain: str, api_key: Optional[str] = None
) -> Dict[str, Any]:
    """Query crt.sh certificate transparency logs. No API key required."""
    del api_key  # unused
    key = cache_key("crtsh", domain)
    if os.path.exists(key):
        with open(key, "r", encoding="utf-8") as f:
            return json.load(f)

    # "%" is a SQL LIKE wildcard on crt.sh; aiohttp will URL-encode it.
    url = "https://crt.sh/"
    params = {"q": f"%.{domain}", "output": "json"}
    data = await fetch_json(session, url, params=params)
    results = {"source": "crt.sh", "domain": domain, "raw": data}

    names = set()
    if isinstance(data, list):
        for entry in data:
            nm = entry.get("name_value") or entry.get("common_name")
            if nm:
                for n in str(nm).splitlines():
                    n = n.strip()
                    if n:
                        names.add(n)
    results["subdomains"] = sorted(names)

    with open(key, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    return results


async def wayback_search(
    session: aiohttp.ClientSession, domain: str, api_key: Optional[str] = None
) -> Dict[str, Any]:
    """Query the Wayback Machine CDX API for URL history."""
    del api_key  # unused
    key = cache_key("wayback", domain)
    if os.path.exists(key):
        with open(key, "r", encoding="utf-8") as f:
            return json.load(f)

    url = "https://web.archive.org/cdx/search/cdx"
    params = {
        "url": f"*.{domain}/*",
        "output": "json",
        "fl": "original,timestamp,statuscode",
        "limit": "1000",
    }
    data = await fetch_json(session, url, params=params)
    results = {"source": "wayback", "domain": domain, "raw": data}

    items = []
    if isinstance(data, list):
        # First row is often a header; skip it.
        for row in data[1:]:
            try:
                items.append({"url": row[0], "timestamp": row[1], "status": row[2]})
            except (IndexError, TypeError):
                continue
    results["captures"] = items

    with open(key, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    return results


async def rdap_search(
    session: aiohttp.ClientSession, domain: str, api_key: Optional[str] = None
) -> Dict[str, Any]:
    """Fetch domain registration data via the rdap.org bootstrap proxy."""
    del api_key  # unused
    key = cache_key("rdap", domain)
    if os.path.exists(key):
        with open(key, "r", encoding="utf-8") as f:
            return json.load(f)

    url = f"https://rdap.org/domain/{domain}"
    data = await fetch_json(session, url)
    results = {"source": "rdap", "domain": domain, "raw": data}

    with open(key, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    return results


async def shodan_search(
    session: aiohttp.ClientSession, domain: str, api_key: Optional[str] = None
) -> Dict[str, Any]:
    """Shodan passive DNS search. Requires a Shodan API key."""
    if not api_key:
        return {"source": "shodan", "domain": domain, "error": "no-api-key"}

    key = cache_key("shodan", domain)
    if os.path.exists(key):
        with open(key, "r", encoding="utf-8") as f:
            return json.load(f)

    url = "https://api.shodan.io/dns/domain/{domain}"
    params = {"key": api_key}
    data = await fetch_json(session, url.format(domain=domain), params=params)
    results = {"source": "shodan", "domain": domain, "raw": data}
    if isinstance(data, dict):
        results["subdomains"] = data.get("subdomains", [])
    else:
        results["subdomains"] = []

    with open(key, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    return results


class PassiveCollector:
    def __init__(
        self,
        session: aiohttp.ClientSession,
        timeout: int = DEFAULT_TIMEOUT,
        api_keys: Optional[Dict[str, str]] = None,
    ):
        self.session = session
        self.timeout = timeout
        self.api_keys = api_keys or {}
        self.collectors = [
            crtsh_search,
            wayback_search,
            rdap_search,
            shodan_search,
        ]

    async def collect_all(
        self, target: str, sources: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Run selected collectors in parallel.

        `sources` filters by collector function name (without the `_search` suffix
        or with it, e.g. `crtsh` or `crtsh_search`).
        """
        target = normalize_target(target)
        if not target:
            return {"target": target, "collected_at": int(time.time()), "results": {}}

        tasks = {}
        for collector in self.collectors:
            name = collector.__name__
            if sources and name not in sources:
                short = name.replace("_search", "")
                if short not in sources:
                    continue

            api_key = self.api_keys.get(name) or self.api_keys.get(
                name.replace("_search", "")
            )
            tasks[asyncio.create_task(collector(self.session, target, api_key))] = name

        results: Dict[str, Any] = {}
        if not tasks:
            return {"target": target, "collected_at": int(time.time()), "results": results}

        completed = await asyncio.gather(*tasks.keys(), return_exceptions=True)
        for task, res in zip(tasks.keys(), completed):
            source = tasks[task].replace("_search", "")
            if isinstance(res, Exception):
                results[source] = {"source": source, "target": target, "error": str(res)}
                continue
            src = res.get("source", res.get("collector", source))
            results[src] = res

        return {"target": target, "collected_at": int(time.time()), "results": results}


async def run_passive(
    target: str,
    sources: Optional[List[str]] = None,
    api_keys: Optional[Dict[str, str]] = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> Dict[str, Any]:
    timeout_obj = aiohttp.ClientTimeout(total=timeout)
    async with aiohttp.ClientSession(headers=DEFAULT_HEADERS, timeout=timeout_obj) as session:
        collector = PassiveCollector(session, timeout=timeout, api_keys=api_keys)
        return await collector.collect_all(target, sources=sources)


def collect_sync(
    target: str,
    sources: Optional[List[str]] = None,
    api_keys: Optional[Dict[str, str]] = None,
    timeout: int = DEFAULT_TIMEOUT,
) -> Dict[str, Any]:
    return asyncio.run(run_passive(target, sources=sources, api_keys=api_keys, timeout=timeout))


def parse_sources(value: Optional[str]) -> Optional[List[str]]:
    if not value:
        return None
    return [s.strip() for s in value.split(",") if s.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description="ALL-RECON passive footprinting module")
    parser.add_argument("target", help="domain to run passive recon against (e.g. example.com)")
    parser.add_argument(
        "--sources",
        help="comma-separated collectors (crtsh, wayback, rdap, shodan)",
        default=None,
    )
    parser.add_argument("--output", "-o", help="path to write JSON output", default=None)
    parser.add_argument("--cache-dir", help="directory for cached responses", default=None)
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="request timeout")
    parser.add_argument("--shodan-key", help="Shodan API key", default=None)
    args = parser.parse_args()

    if args.cache_dir:
        os.environ["ALLRECON_CACHE_DIR"] = args.cache_dir

    api_keys = {}
    if args.shodan_key:
        api_keys["shodan"] = args.shodan_key

    sources = parse_sources(args.sources)
    result = collect_sync(args.target, sources=sources, api_keys=api_keys, timeout=args.timeout)

    json_out = json.dumps(result, indent=2)
    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(json_out)
            print(f"[+] passive recon saved to {args.output}")
        except OSError as exc:
            print(f"[!] failed to write {args.output}: {exc}", file=sys.stderr)
            return 1
    else:
        print(json_out)

    return 0


if __name__ == "__main__":
    sys.exit(main())
