"""Self-signed TLS certificate provisioning and rotation.

Used by the container entrypoint for WEBSSH_TLS_MODE=self-signed: it creates
a private certificate for a domain or bare IP on first boot and regenerates
it automatically once it nears expiry. Run standalone:

    python -m app.tls_certificates --domain 192.168.1.10 \
        --cert-dir /app/data/tls --renew-within-days 30

Exits 0 when a usable certificate is in place, 2 when one was rotated.
"""

import argparse
import datetime
import ipaddress
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID


def _subject_alternative_name(domain):
    try:
        return x509.IPAddress(ipaddress.ip_address(domain))
    except ValueError:
        return x509.DNSName(domain)


def _load_certificate(cert_file):
    return x509.load_pem_x509_certificate(Path(cert_file).read_bytes())


def certificate_expiry(cert_file):
    """Return the certificate's notAfter as an aware datetime, or None."""
    try:
        return _load_certificate(cert_file).not_valid_after_utc
    except (FileNotFoundError, ValueError, TypeError):
        return None


def needs_renewal(cert_file, *, renew_within_days=30, now=None):
    """True when the certificate is missing, unreadable, or near expiry."""
    expiry = certificate_expiry(cert_file)
    if expiry is None:
        return True
    now = now or datetime.datetime.now(datetime.timezone.utc)
    margin = datetime.timedelta(days=max(0, renew_within_days))
    return expiry <= now + margin


def generate_self_signed(domain, cert_file, key_file, *, days=825):
    """Write a fresh EC self-signed certificate covering ``domain``."""
    domain = str(domain or '').strip()
    if not domain:
        raise ValueError('a domain or IP address is required')

    key = ec.generate_private_key(ec.SECP256R1())
    now = datetime.datetime.now(datetime.timezone.utc)
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, domain[:64]),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, 'WebSSH'),
    ])
    san = x509.SubjectAlternativeName([_subject_alternative_name(domain)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=days))
        .add_extension(san, critical=False)
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=True,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
        .sign(key, hashes.SHA256())
    )

    cert_path = Path(cert_file)
    key_path = Path(key_file)
    cert_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    key_path.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    key_path.chmod(0o600)
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    return cert_path


def ensure_certificate(
    domain,
    cert_file,
    key_file,
    *,
    renew_within_days=30,
    days=825,
):
    """Create or rotate the certificate; return (path, rotated)."""
    if not needs_renewal(
        cert_file, renew_within_days=renew_within_days
    ):
        return Path(cert_file), False
    generate_self_signed(domain, cert_file, key_file, days=days)
    return Path(cert_file), True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Ensure a self-signed TLS certificate exists and is fresh.'
    )
    parser.add_argument('--domain', required=True,
                        help='domain name or IP address to cover')
    parser.add_argument('--cert-dir', required=True,
                        help='directory holding fullchain.pem/privkey.pem')
    parser.add_argument('--renew-within-days', type=int, default=30)
    parser.add_argument('--days', type=int, default=825,
                        help='validity of a newly generated certificate')
    args = parser.parse_args(argv)

    cert_dir = Path(args.cert_dir)
    cert_file = cert_dir / 'fullchain.pem'
    key_file = cert_dir / 'privkey.pem'
    _path, rotated = ensure_certificate(
        args.domain,
        cert_file,
        key_file,
        renew_within_days=args.renew_within_days,
        days=args.days,
    )
    if rotated:
        print(f'TLS certificate for {args.domain} generated/rotated: {cert_file}')
        return 2
    print(f'TLS certificate for {args.domain} is current: {cert_file}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
