"""Offline tests for the expanded ALL-RECON modules; no network calls are made."""
import importlib.util
import ipaddress
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, "modules", path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


asn = load_module("asn_recon", "asn_recon.py")
http = load_module("http_fingerprint", "http_fingerprint.py")
dns = load_module("dns_email_audit", "dns_email_audit.py")


class ASNTests(unittest.TestCase):
    def test_normalizes_domain_and_scheme(self):
        self.assertEqual(asn.normalize_target("EXAMPLE.COM."), "example.com")
        self.assertEqual(asn.normalize_target("https://Example.com/path?q=1"), "example.com")

    def test_normalizes_ip_and_host_port(self):
        self.assertEqual(asn.normalize_target("192.0.2.10"), "192.0.2.10")
        self.assertEqual(asn.normalize_target("example.com:443"), "example.com")
        self.assertEqual(asn.normalize_target("2001:db8::1"), str(ipaddress.ip_address("2001:db8::1")))

    def test_rejects_invalid_target(self):
        with self.assertRaises(ValueError):
            asn.normalize_target("not a target")


class HTTPFingerprintTests(unittest.TestCase):
    def test_domain_defaults_to_https(self):
        self.assertEqual(http.normalize_url("example.com"), "https://example.com")

    def test_rejects_unsupported_scheme_and_embedded_credentials(self):
        with self.assertRaises(ValueError):
            http.normalize_url("ftp://example.com")
        with self.assertRaises(ValueError):
            http.normalize_url("https://user:pass@example.com")

    def test_detects_framework_clue_without_network(self):
        clues = http.detect_technologies({}, '<html><script src="/_next/static/app.js"></script></html>')
        self.assertIn("Next.js", clues)


class DNSEmailAuditTests(unittest.TestCase):
    def test_normalizes_domain(self):
        self.assertEqual(dns.normalize_domain("Example.COM."), "example.com")

    def test_rejects_ip_address(self):
        with self.assertRaises(ValueError):
            dns.normalize_domain("192.0.2.10")

    def _empty_records(self):
        keys = ("txt", "dmarc", "mx", "caa", "dnskey", "mta_sts", "tls_rpt")
        raw = {key: {"records": [], "error": None} for key in keys}
        raw["dkim"] = {
            selector: {"records": [], "error": None}
            for selector in dns.DKIM_SELECTORS
        }
        return raw

    def test_flags_multiple_spf_and_monitoring_only_dmarc(self):
        raw = self._empty_records()
        raw["txt"]["records"] = [
            {"value": "v=spf1 include:mail.example -all", "type": "TXT"},
            {"value": "v=spf1 include:other.example -all", "type": "TXT"},
        ]
        raw["dmarc"]["records"] = [{"value": "v=DMARC1; p=none", "type": "TXT"}]
        findings = dns.assess("example.com", raw)
        titles = {finding["title"] for finding in findings}
        self.assertIn("Multiple SPF records", titles)
        self.assertIn("DMARC is monitoring-only", titles)

    def test_missing_spf_and_dmarc_are_reported_with_context(self):
        findings = dns.assess("example.com", self._empty_records())
        titles = {finding["title"] for finding in findings}
        self.assertIn("No SPF policy observed", titles)
        self.assertIn("DMARC record not observed", titles)
        self.assertIn("No tested DKIM selectors observed", titles)


if __name__ == "__main__":
    unittest.main()
