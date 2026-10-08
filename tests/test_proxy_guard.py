import ipaddress

import pytest

from app.proxy_guard import TrustedProxyGuard


def _wsgi_recorder(environ, start_response):
    start_response('200 OK', [('Content-Type', 'text/plain')])
    return [environ.get('HTTP_X_FORWARDED_FOR', '').encode('utf-8')]


def _start_response(status, headers):
    return lambda chunk: None


def _guard(networks):
    return TrustedProxyGuard(
        _wsgi_recorder,
        [ipaddress.ip_network(cidr) for cidr in networks],
    )


@pytest.mark.parametrize('peer,expected_body', [
    ('10.1.2.3', b'203.0.113.9'),
    ('::ffff:10.1.2.3', b'203.0.113.9'),
])
def test_trusted_peer_forwards_xff(peer, expected_body):
    guard = _guard(['10.0.0.0/8'])
    environ = {
        'REMOTE_ADDR': peer,
        'HTTP_X_FORWARDED_FOR': '203.0.113.9',
    }
    body = b''.join(guard(environ, _start_response))
    assert body == expected_body


@pytest.mark.parametrize('peer,xff', [
    ('203.0.113.9', '198.51.100.7'),
    ('fd00::1', '198.51.100.7'),
    ('', '198.51.100.7'),
])
def test_untrusted_peer_headers_are_stripped(peer, xff):
    guard = _guard(['10.0.0.0/8'])
    environ = {
        'REMOTE_ADDR': peer,
        'HTTP_X_FORWARDED_FOR': xff,
        'HTTP_X_FORWARDED_PROTO': 'https',
        'HTTP_X_FORWARDED_HOST': 'evil.example',
    }
    captured = {}
    body = b''.join(guard(environ, _start_response))
    assert body == b''
    assert 'HTTP_X_FORWARDED_FOR' not in environ
    assert 'HTTP_X_FORWARDED_PROTO' not in environ
    assert 'HTTP_X_FORWARDED_HOST' not in environ
    assert captured == {}


def test_zone_index_suffix_is_ignored_for_peer_matching():
    guard = _guard(['fe80::/10'])
    environ = {
        'REMOTE_ADDR': 'fe80::1%eth0',
        'HTTP_X_FORWARDED_FOR': '203.0.113.9',
    }
    body = b''.join(guard(environ, _start_response))
    assert body == b'203.0.113.9'


def test_unparseable_peer_is_never_trusted():
    guard = _guard(['0.0.0.0/0'])
    environ = {
        'REMOTE_ADDR': 'not-an-ip',
        'HTTP_X_FORWARDED_FOR': '203.0.113.9',
    }
    body = b''.join(guard(environ, _start_response))
    assert body == b''
