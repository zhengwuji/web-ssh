"""Explicit gateway identities; ordinary SSH validation remains unchanged."""
import hashlib
import json
import re
import unicodedata
import uuid


_UNSAFE_PREFIX_CHARACTER = re.compile(r"[^A-Za-z0-9_]")


def parse_selector(value):
    """Return the exact user/target pair or reject an ambiguous selector."""
    if not isinstance(value, str) or ":" not in value:
        raise ValueError("Invalid gateway selector")
    if value.startswith("ticket-") or "#" in value:
        raise ValueError("Gateway tickets and alternate separators are not supported")
    if any(unicodedata.category(c) in {"Cc", "Cf", "Cs", "Zl", "Zp"} for c in value):
        raise ValueError("Invalid gateway selector")
    if len(value.encode("utf-8")) > 128:
        raise ValueError("Gateway selector exceeds 128 UTF-8 bytes")
    user, target = value.split(":", 1)
    if not all(part and part == part.strip() for part in (user, target)):
        raise ValueError("Gateway user and target are required without surrounding whitespace")
    return user, target


def tmux_name(prefix, host, port, selector, user_id):
    parse_selector(selector)
    safe_prefix = _UNSAFE_PREFIX_CHARACTER.sub("_", prefix)[:80]
    identity = json.dumps([str(user_id), host, int(port), selector], ensure_ascii=True)
    digest = hashlib.sha256(identity.encode("ascii")).hexdigest()[:16]
    return f"{safe_prefix}_wg_{digest}_{uuid.uuid4().hex}"
