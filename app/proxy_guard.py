"""Guard X-Forwarded-* handling so only trusted proxy peers can set it.

ProxyFix trusts the last N hops of X-Forwarded-For unconditionally. On a
directly reachable instance an attacker can therefore rotate the header to
defeat per-IP rate limits (login, OTP, MFA). This middleware resolves that:
forwarding headers are honored only when the direct socket peer falls inside
an explicitly configured CIDR; otherwise the headers are dropped before
ProxyFix ever sees them.
"""

import ipaddress


class TrustedProxyGuard:
    """WSGI middleware enforcing a CIDR allowlist in front of ProxyFix."""

    def __init__(self, app, networks):
        self.app = app
        self.networks = tuple(networks)

    def _peer_is_trusted(self, environ):
        remote = environ.get('REMOTE_ADDR') or ''
        # Strip an IPv6 zone index (fe80::1%eth0) before parsing.
        remote = remote.split('%', 1)[0]
        try:
            peer = ipaddress.ip_address(remote)
        except ValueError:
            return False
        # Dual-stack sockets surface IPv4 peers as IPv4-mapped IPv6.
        if peer.version == 6 and peer.ipv4_mapped is not None:
            peer = peer.ipv4_mapped
        for network in self.networks:
            if peer in network:
                return True
        return False

    def __call__(self, environ, start_response):
        if not self._peer_is_trusted(environ):
            for header in (
                'HTTP_X_FORWARDED_FOR',
                'HTTP_X_FORWARDED_PROTO',
                'HTTP_X_FORWARDED_HOST',
                'HTTP_X_FORWARDED_PORT',
                'HTTP_X_FORWARDED_PREFIX',
            ):
                environ.pop(header, None)
        return self.app(environ, start_response)
