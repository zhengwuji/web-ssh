"""Runtime WebAuthn relying-party context.

Passkeys bind credentials to a relying-party ID and origin. Deployments that
configure WEBAUTHN_RP_ID/WEBAUTHN_ORIGIN explicitly keep using those values;
otherwise the values derive from the incoming request so a homelab admin can
turn passkeys on from the admin panel without editing environment files.

Deriving the RP ID from the Host header is only honoured when the operator
left both keys unset: credentials then scope to whatever host served the
ceremony (behind a proxy, ProxyFix must be guarded — see TRUSTED_PROXY_CIDRS).
"""

from urllib.parse import urlsplit

from flask import request

import config


def _explicit_origin():
    if config.WEBAUTHN_ORIGIN_EXPLICIT:
        return config.WEBAUTHN_ORIGIN.strip()
    return None


def _explicit_rp_id():
    if config.WEBAUTHN_RP_ID_EXPLICIT:
        return config.WEBAUTHN_RP_ID.strip()
    return None


def _request_host_parts():
    host_header = request.host if request else None
    if not host_header:
        return None, None
    try:
        split = urlsplit(f'//{host_header}')
    except ValueError:
        return None, None
    return split.hostname, split.port


def _default_port_for(scheme):
    return 443 if scheme == 'https' else 80 if scheme == 'http' else None


def effective_rp_id():
    """The configured RP ID, or the request host without its port."""
    explicit = _explicit_rp_id()
    if explicit:
        return explicit
    hostname, _port = _request_host_parts()
    if hostname:
        return hostname
    return config.WEBAUTHN_RP_ID


def effective_origin():
    """The configured origin, or the request's scheme://host[:port]."""
    explicit = _explicit_origin()
    if explicit:
        return explicit
    scheme = (request.scheme if request else '') or 'https'
    hostname, port = _request_host_parts()
    if not hostname:
        return config.WEBAUTHN_ORIGIN
    if port and port != _default_port_for(scheme):
        return f'{scheme}://{hostname}:{port}'
    return f'{scheme}://{hostname}'
