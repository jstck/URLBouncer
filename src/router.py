import re
import logging
from urllib.parse import urlparse


def route_url(url: str, config: dict) -> str:
    """
    Evaluate URL against rules in order. Return the Chrome profile directory name.
    Rules are matched top-to-bottom; first match wins.

    Rule 'match' semantics:
    - Plain string: case-insensitive substring match against the hostname
    - If pattern contains '/' or '?': matched against the full URL
    - Prefix 're:': regex matched against the full URL (case-insensitive)
    """
    rules = config.get("rules", [])
    default = config.get("default_profile", "Default")

    try:
        parsed = urlparse(url)
        netloc = parsed.netloc.lower()
        full_url_lower = url.lower()
    except Exception:
        logging.warning(f"Could not parse URL: {url!r}")
        return default

    for rule in rules:
        pattern = rule.get("match", "")
        profile = rule.get("profile", default)

        if not pattern:
            continue

        try:
            if pattern.startswith("re:"):
                if re.search(pattern[3:], url, re.IGNORECASE):
                    logging.info(f"Rule match (regex {pattern!r}): {url!r} -> {profile!r}")
                    return profile
            elif "/" in pattern or "?" in pattern:
                if pattern.lower() in full_url_lower:
                    logging.info(f"Rule match (full URL {pattern!r}): {url!r} -> {profile!r}")
                    return profile
            else:
                if pattern.lower() in netloc:
                    logging.info(f"Rule match (host {pattern!r}): {url!r} -> {profile!r}")
                    return profile
        except re.error as e:
            logging.warning(f"Bad regex in rule {rule!r}: {e}")
            continue

    logging.info(f"No rule matched, using default profile {default!r}: {url!r}")
    return default
