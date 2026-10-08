#!/bin/bash
set -euo pipefail

# Resolve one canonical persistent root for application state and the
# encryption root. Relative paths are intentionally rejected because backup,
# restore, and secret rotation all treat DATA_DIR as an absolute trust boundary.
DATA_DIR="${DATA_DIR:-/app/data}"
case "$DATA_DIR" in
    /*) ;;
    *)
        echo "ERROR: DATA_DIR must be an absolute path." >&2
        exit 1
        ;;
esac
DATA_DIR="$(python -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$DATA_DIR")"
export DATA_DIR

# Data directories
mkdir -p "$DATA_DIR/logs" "$DATA_DIR/keys"
chmod 700 "$DATA_DIR" "$DATA_DIR/logs" "$DATA_DIR/keys"

# SECRET_KEY resolution order:
#   1) SECRET_KEY environment variable (explicit; wins, e.g. external secrets)
#   2) persisted file under DATA_DIR (survives restarts when DATA_DIR is a volume)
#   3) auto-generated and persisted (zero-config first run)
# Known placeholders (e.g. the compose template) are treated as "not set".
SECRET_KEY_FILE="$DATA_DIR/secret_key"
LEGACY_SECRET_KEY_FILE="/app/data/secret_key"

_sk="${SECRET_KEY:-}"
case "$(printf '%s' "$_sk" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    ""|"<your-secret-key>"|"changeme"|"secret"|"your-secret-key")
        _sk=""
        ;;
esac

if [ -z "$_sk" ]; then
    if [ "$SECRET_KEY_FILE" != "$LEGACY_SECRET_KEY_FILE" ] && [ -f "$LEGACY_SECRET_KEY_FILE" ]; then
        if [ ! -f "$SECRET_KEY_FILE" ]; then
            echo "ERROR: a legacy secret exists at $LEGACY_SECRET_KEY_FILE but DATA_DIR is $DATA_DIR." >&2
            echo "Copy that file to $SECRET_KEY_FILE with mode 600 before starting WebSSH." >&2
            exit 1
        fi
        if ! cmp -s "$LEGACY_SECRET_KEY_FILE" "$SECRET_KEY_FILE"; then
            echo "ERROR: conflicting secret_key files exist under /app/data and DATA_DIR." >&2
            exit 1
        fi
    fi
    if [ -f "$SECRET_KEY_FILE" ]; then
        _sk="$(cat "$SECRET_KEY_FILE")"
        echo "Loaded persisted SECRET_KEY from $SECRET_KEY_FILE"
    else
        _sk="$(python -c 'import secrets; print(secrets.token_hex(32))')"
        if (umask 077; printf '%s\n' "$_sk" > "$SECRET_KEY_FILE"); then
            echo "Generated a new SECRET_KEY and persisted it to $SECRET_KEY_FILE"
            echo "   Keep $DATA_DIR on a volume so it survives container re-creation."
        else
            echo "ERROR: could not write $SECRET_KEY_FILE -- mount a writable volume on $DATA_DIR." >&2
            exit 1
        fi
    fi
    export SECRET_KEY="$_sk"
fi

# ---------------------------------------------------------------------------
# Optional TLS termination (WEBSSH_TLS_MODE): off | self-signed | acme | manual
# ---------------------------------------------------------------------------
GUNICORN_TLS_ARGS=""
TLS_MODE="${WEBSSH_TLS_MODE:-off}"
TLS_CERT_DIR="${WEBSSH_TLS_CERT_DIR:-$DATA_DIR/tls}"
TLS_CERT_FILE="$TLS_CERT_DIR/fullchain.pem"
TLS_KEY_FILE="$TLS_CERT_DIR/privkey.pem"
TLS_DOMAIN="${WEBSSH_TLS_DOMAIN:-}"

case "$TLS_MODE" in
    off)
        ;;
    self-signed)
        if [ -z "$TLS_DOMAIN" ]; then
            echo "ERROR: WEBSSH_TLS_MODE=self-signed requires WEBSSH_TLS_DOMAIN (a domain or IP)." >&2
            exit 1
        fi
        mkdir -p "$TLS_CERT_DIR"
        chmod 700 "$TLS_CERT_DIR" || true
        # The CLI exits 2 when it generated/rotated the certificate, which is
        # the normal first-run outcome; only a real failure may abort startup.
        _tls_status=0
        python -m app.tls_certificates             --domain "$TLS_DOMAIN"             --cert-dir "$TLS_CERT_DIR"             --renew-within-days "${WEBSSH_TLS_RENEW_WITHIN_DAYS:-30}" || _tls_status=$?
        case "$_tls_status" in
            0|2) ;;
            *)
                echo "ERROR: self-signed certificate setup failed (exit $_tls_status)." >&2
                exit 1
                ;;
        esac
        # Background watchdog keeps rotating the private certificate; it
        # survives the exec below as a detached child of the new PID 1.
        (
            while :; do
                sleep "${WEBSSH_TLS_RENEWAL_CHECK_HOURS:-12}h" 2>/dev/null || sleep 43200
                python -m app.tls_certificates                     --domain "$TLS_DOMAIN"                     --cert-dir "$TLS_CERT_DIR"                     --renew-within-days "${WEBSSH_TLS_RENEW_WITHIN_DAYS:-30}"                     >/dev/null 2>&1 || true
            done
        ) &
        GUNICORN_TLS_ARGS="--certfile=$TLS_CERT_FILE --keyfile=$TLS_KEY_FILE"
        echo "TLS: serving HTTPS with an auto-rotated self-signed certificate for $TLS_DOMAIN"
        ;;
    acme)
        if [ -z "$TLS_DOMAIN" ]; then
            echo "ERROR: WEBSSH_TLS_MODE=acme requires WEBSSH_TLS_DOMAIN." >&2
            exit 1
        fi
        if [ -z "${WEBSSH_TLS_EMAIL:-}" ]; then
            echo "ERROR: WEBSSH_TLS_MODE=acme requires WEBSSH_TLS_EMAIL." >&2
            exit 1
        fi
        ACME_HOME="$TLS_CERT_DIR/acme-home"
        mkdir -p "$TLS_CERT_DIR"
        chmod 700 "$TLS_CERT_DIR" || true
        if [ ! -x "$ACME_HOME/acme.sh" ]; then
            echo "TLS: installing acme.sh (requires outbound network access)"
            curl -sSLf https://get.acme.sh |
                ACME_HOME="$ACME_HOME" sh -s -- install --home "$ACME_HOME" --no-cron || {
                echo "ERROR: acme.sh installation failed; check outbound connectivity." >&2
                exit 1
            }
        fi
        _extra_issue_args=""
        case "$TLS_DOMAIN" in
            *.*) _extra_issue_args="" ;;
            *)
                # A bare IP: Let's Encrypt only signs IP identifiers with the
                # short-lived profile; acme.sh must support it (>= 3.1).
                _extra_issue_args="--certificate-profile shortlived"
                ;;
        esac
        if [ ! -s "$TLS_CERT_FILE" ]; then
            echo "TLS: issuing certificate for $TLS_DOMAIN (standalone HTTP-01 on port ${WEBSSH_TLS_ACME_PORT:-80})"
            "$ACME_HOME/acme.sh" --issue                 --domain "$TLS_DOMAIN"                 --standalone                 --server "${WEBSSH_TLS_CA:-letsencrypt}"                 --accountemail "$WEBSSH_TLS_EMAIL"                 --keylength ec-256                 $_extra_issue_args || {
                echo "ERROR: certificate issuance failed; verify DNS/port 80 reachability." >&2
                exit 1
            }
            "$ACME_HOME/acme.sh" --install-cert                 --domain "$TLS_DOMAIN"                 --ecc                 --fullchain-file "$TLS_CERT_FILE"                 --key-file "$TLS_KEY_FILE"                 --reloadcmd "kill -HUP 1 2>/dev/null || true" || exit 1
        fi
        # Renewal watchdog: acme.sh's own cron cannot run inside a container,
        # so re-run its renewal pass on a fixed cadence. Successful renewals
        # re-install the files and HUP the gunicorn master (PID 1 after exec).
        (
            while :; do
                sleep "${WEBSSH_TLS_RENEWAL_CHECK_HOURS:-12}h" 2>/dev/null || sleep 43200
                "$ACME_HOME/acme.sh" --cron --home "$ACME_HOME" >/dev/null 2>&1 || true
            done
        ) &
        GUNICORN_TLS_ARGS="--certfile=$TLS_CERT_FILE --keyfile=$TLS_KEY_FILE"
        echo "TLS: serving HTTPS with an ACME-managed certificate for $TLS_DOMAIN"
        ;;
    manual)
        if [ ! -s "$TLS_CERT_FILE" ] || [ ! -s "$TLS_KEY_FILE" ]; then
            echo "ERROR: WEBSSH_TLS_MODE=manual expects PEM files at:" >&2
            echo "  $TLS_CERT_FILE" >&2
            echo "  $TLS_KEY_FILE" >&2
            exit 1
        fi
        GUNICORN_TLS_ARGS="--certfile=$TLS_CERT_FILE --keyfile=$TLS_KEY_FILE"
        echo "TLS: serving HTTPS with operator-provided certificates"
        ;;
    *)
        echo "ERROR: WEBSSH_TLS_MODE must be one of off, self-signed, acme, manual." >&2
        exit 1
        ;;
esac
if [ -n "$GUNICORN_TLS_ARGS" ]; then
    export GUNICORN_TLS_ARGS
    chmod 600 "$TLS_KEY_FILE" || true
fi

exec "$@"
