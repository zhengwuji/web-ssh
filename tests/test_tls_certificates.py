import datetime
import ipaddress
from pathlib import Path

import pytest
from cryptography import x509

from app import tls_certificates


def _load_cert(path):
    return x509.load_pem_x509_certificate(Path(path).read_bytes())


def test_generate_self_signed_covers_dns_domain(tmp_path):
    cert_file = tmp_path / 'fullchain.pem'
    key_file = tmp_path / 'privkey.pem'

    tls_certificates.generate_self_signed(
        'ssh.example.com', cert_file, key_file
    )

    cert = _load_cert(cert_file)
    sans = cert.extensions.get_extension_for_class(
        x509.SubjectAlternativeName
    ).value
    assert sans.get_values_for_type(x509.DNSName) == ['ssh.example.com']
    assert key_file.read_bytes().startswith(b'-----BEGIN PRIVATE KEY')
    import os
    if os.name != 'nt':  # Windows does not preserve POSIX mode bits.
        assert key_file.stat().st_mode & 0o777 == 0o600


def test_generate_self_signed_covers_bare_ip(tmp_path):
    cert_file = tmp_path / 'fullchain.pem'

    tls_certificates.generate_self_signed(
        '192.168.1.10', cert_file, tmp_path / 'privkey.pem'
    )

    cert = _load_cert(cert_file)
    sans = cert.extensions.get_extension_for_class(
        x509.SubjectAlternativeName
    ).value
    assert sans.get_values_for_type(x509.IPAddress) == [
        ipaddress.ip_address('192.168.1.10')
    ]


def test_missing_certificate_needs_renewal(tmp_path):
    assert tls_certificates.needs_renewal(tmp_path / 'absent.pem')


def test_fresh_certificate_is_kept_and_expired_is_rotated(tmp_path):
    cert_file = tmp_path / 'fullchain.pem'
    key_file = tmp_path / 'privkey.pem'
    tls_certificates.generate_self_signed(
        'ssh.example.com', cert_file, key_file
    )

    path, rotated = tls_certificates.ensure_certificate(
        'ssh.example.com', cert_file, key_file
    )
    assert rotated is False
    assert path == cert_file

    # A certificate expiring within the renewal window must rotate.
    now = datetime.datetime.now(datetime.timezone.utc)
    assert tls_certificates.needs_renewal(
        cert_file,
        renew_within_days=10_000,
        now=now,
    )
    path, rotated = tls_certificates.ensure_certificate(
        'ssh.example.com', cert_file, key_file, renew_within_days=10_000
    )
    assert rotated is True
    assert tls_certificates.certificate_expiry(cert_file) > now


def test_generate_requires_a_domain(tmp_path):
    with pytest.raises(ValueError):
        tls_certificates.generate_self_signed(
            '', tmp_path / 'fullchain.pem', tmp_path / 'privkey.pem'
        )


def test_cli_reports_current_certificate(tmp_path, capsys):
    exit_code = tls_certificates.main([
        '--domain', '10.0.0.5',
        '--cert-dir', str(tmp_path),
    ])
    assert exit_code in {0, 2}
    exit_code = tls_certificates.main([
        '--domain', '10.0.0.5',
        '--cert-dir', str(tmp_path),
    ])
    assert exit_code == 0
    assert 'is current' in capsys.readouterr().out
