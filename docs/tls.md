# Built-in HTTPS and automatic certificates

WebSSH can terminate TLS itself and keep the certificate renewed
automatically, similar to how 3x-ui manages its panel certificate. Configure
it entirely through environment variables — no manual cert shuffling.

| `WEBSSH_TLS_MODE` | What it does |
| --- | --- |
| `off` *(default)* | Plain HTTP listener; put your own reverse proxy in front. |
| `self-signed` | Generates a private certificate for a **domain or bare IP** on first boot and **rotates it automatically** (default validity 825 days, rotated 30 days before expiry). |
| `acme` | Issues a **publicly trusted** certificate through [acme.sh](https://github.com/acmesh-official/acme.sh) (HTTP-01) and **renews automatically**. Domains work with Let's Encrypt/ZeroSSL; bare IPs use the Let's Encrypt short-lived profile. |
| `manual` | Serves operator-provided PEM files. |

All modes store material under `$DATA_DIR/tls/` (default `/app/data/tls`),
which lives on your persistent volume, and start gunicorn with TLS on the
normal `PORT` (5000).

## Domain certificate (recommended)

```yaml
# docker-compose.yml
services:
  webssh:
    # ...
    environment:
      WEBSSH_TLS_MODE: acme
      WEBSSH_TLS_DOMAIN: ssh.example.com
      WEBSSH_TLS_EMAIL: you@example.com
    ports:
      - "80:80"      # HTTP-01 challenge, ACME only
      - "443:5000"   # HTTPS
```

Requirements:

- `ssh.example.com` resolves publicly to this host.
- Port 80 is reachable from the internet during issuance and renewal.
- Outbound HTTPS is available (acme.sh is installed on first boot under
  `$DATA_DIR/tls/acme-home/`).

Renewal runs inside the container on a watchdog loop (default every 12
hours); acme.sh only re-issues when the certificate is actually due, then
reinstalls the files and signals the gunicorn master to pick them up
(`SIGHUP`). No restart required.

## Bare IP address

Public CAs only sign IP identifiers under short-lived profiles:

```yaml
environment:
  WEBSSH_TLS_MODE: acme
  WEBSSH_TLS_DOMAIN: 203.0.113.10
  WEBSSH_TLS_EMAIL: you@example.com
```

If your ACME account cannot issue IP certificates, use `self-signed` mode,
which supports IPs (as a SAN) with automatic rotation:

```yaml
environment:
  WEBSSH_TLS_MODE: self-signed
  WEBSSH_TLS_DOMAIN: 192.168.1.10
```

Browsers will show a trust warning for self-signed certificates; passkeys
and SSH connections are unaffected because the browser user accepts the
certificate once.

## Tuning

| Variable | Default | Purpose |
| --- | --- | --- |
| `WEBSSH_TLS_CA` | `letsencrypt` | ACME server (`letsencrypt` or `zerossl`). |
| `WEBSSH_TLS_RENEW_WITHIN_DAYS` | `30` | Rotate the self-signed certificate this many days before expiry. |
| `WEBSSH_TLS_RENEWAL_CHECK_HOURS` | `12` | Renewal watchdog cadence. |
| `WEBSSH_TLS_CERT_DIR` | `$DATA_DIR/tls` | Certificate/key directory (`fullchain.pem`, `privkey.pem`). |
| `WEBSSH_TLS_ACME_PORT` | `80` | Port acme.sh binds for the HTTP-01 challenge. |

## Notes

- The container health probe speaks HTTPS automatically when a TLS mode is
  active (it accepts untrusted certificates for the probe itself).
- `manual` mode expects `fullchain.pem` and `privkey.pem` inside
  `WEBSSH_TLS_CERT_DIR` and fails fast otherwise.
- The key file is always chmod 600; the directory is chmod 700.
- When TLS terminates inside WebSSH, passkeys derive their relying-party ID
  from the request host automatically; set `WEBAUTHN_RP_ID` /
  `WEBAUTHN_ORIGIN` explicitly if you serve the panel under a different
  public name than the certificate's domain.
