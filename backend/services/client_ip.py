"""Resolve the real client address behind Render's proxy.

``ProxyFix`` (configured in ``app.py`` from ``TRUSTED_PROXY_HOPS``) rewrites
``REMOTE_ADDR`` from the right-most N ``X-Forwarded-For`` entries, i.e. the
entries appended by proxies we trust. Entries further left were written by the
client and are never used.

This module adds the checks ProxyFix does not do:

* The resolved value must parse as an IP address. If a trusted hop ever passes
  through junk, we fall back to the directly connected peer instead of keying
  the rate limiter on attacker-chosen text.
* For rate limiting, IPv6 clients are keyed by their /64 network: one
  subscriber usually controls a whole /64 and could otherwise rotate through
  2^64 addresses to reset their budget.
"""

import ipaddress

from flask import request

IPV6_RATE_LIMIT_PREFIX = 64


def _parse(value):
    if not value:
        return None
    try:
        return ipaddress.ip_address(str(value).strip())
    except ValueError:
        return None


def _direct_peer():
    original = request.environ.get("werkzeug.proxy_fix.orig") or {}
    return original.get("REMOTE_ADDR") or request.environ.get("REMOTE_ADDR")


def client_ip():
    """Return the validated client IP as a string, or None."""
    parsed = _parse(request.remote_addr) or _parse(_direct_peer())
    if parsed is None:
        return None
    if isinstance(parsed, ipaddress.IPv6Address) and parsed.ipv4_mapped:
        parsed = parsed.ipv4_mapped
    return str(parsed)


def rate_limit_ip_key():
    """Return the identity used for per-IP rate limits."""
    ip = client_ip()
    if ip is None:
        return "unknown"
    parsed = ipaddress.ip_address(ip)
    if isinstance(parsed, ipaddress.IPv6Address):
        network = ipaddress.ip_network(
            "{}/{}".format(ip, IPV6_RATE_LIMIT_PREFIX), strict=False,
        )
        return str(network)
    return ip
