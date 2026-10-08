#!/bin/sh
# WebSSH one-command installer.
#
# Two install modes share one entry point:
#   docker  (default) - pull the published image and run it through Compose
#   source            - build a local virtualenv and run gunicorn directly
#
# The installer is idempotent: re-running it keeps the existing data
# directory, generated application secret, and TLS material.
#
# Usage:
#   ./install.sh [--mode docker|source] [options]
#
# Run `./install.sh --help` for the full option list.

set -eu

PROGRAM_NAME="WebSSH installer"
DEFAULT_PORT=5000
DEFAULT_DIR="./webssh-deployment"
IMAGE="ghcr.io/zhengwuji/web-ssh:latest"
READY_TIMEOUT_SECONDS=120

MODE="docker"
INSTALL_DIR="$DEFAULT_DIR"
PORT="$DEFAULT_PORT"
TLS_MODE="off"
TLS_DOMAIN=""
TLS_EMAIL=""
START_SERVICE="true"
ALLOW_INTERNAL="false"
PULL_IMAGE="true"

log() {
    printf '%s\n' "$*"
}

warn() {
    printf '%s\n' "WARNING: $*" >&2
}

fail() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
WebSSH one-command installer

Usage:
  ./install.sh [options]

Options:
  --mode docker|source   Install mode. Default: docker
  --dir PATH             Install directory. Default: ./webssh-deployment
  --port PORT            Published port. Default: 5000
  --tls MODE             off | self-signed | manual | acme. Default: off
  --domain NAME          TLS domain or IP. Required for self-signed and acme
  --email ADDRESS        ACME account email. Required for acme
  --allow-internal-ssh   Allow SSH connections to loopback and private targets
  --no-start             Prepare files only; do not start the service
  --no-pull              Skip the image pull step (docker mode)
  --help                 Show this message

Examples:
  ./install.sh
  ./install.sh --mode docker --port 8443 --tls self-signed --domain webssh.lan
  ./install.sh --mode source --dir /opt/webssh --port 5000

The installer never prints the generated SECRET_KEY. It is written to
<dir>/.env with 0600 permissions.
USAGE
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$2"
}

generate_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import secrets; print(secrets.token_hex(32))'
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        python -c 'import secrets; print(secrets.token_hex(32))'
        return 0
    fi
    fail "openssl or python is required to generate the application secret."
}

python_is_supported() {
    "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
        >/dev/null 2>&1
}

python_command() {
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && python_is_supported "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    fail "Python 3.10 or newer is required for --mode source."
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                [ "$#" -ge 2 ] || fail "--mode requires a value."
                MODE="$2"
                shift 2
                ;;
            --dir)
                [ "$#" -ge 2 ] || fail "--dir requires a value."
                INSTALL_DIR="$2"
                shift 2
                ;;
            --port)
                [ "$#" -ge 2 ] || fail "--port requires a value."
                PORT="$2"
                shift 2
                ;;
            --tls)
                [ "$#" -ge 2 ] || fail "--tls requires a value."
                TLS_MODE="$2"
                shift 2
                ;;
            --domain)
                [ "$#" -ge 2 ] || fail "--domain requires a value."
                TLS_DOMAIN="$2"
                shift 2
                ;;
            --email)
                [ "$#" -ge 2 ] || fail "--email requires a value."
                TLS_EMAIL="$2"
                shift 2
                ;;
            --allow-internal-ssh)
                ALLOW_INTERNAL="true"
                shift
                ;;
            --no-start)
                START_SERVICE="false"
                shift
                ;;
            --no-pull)
                PULL_IMAGE="false"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1 (run with --help)."
                ;;
        esac
    done

    case "$MODE" in
        docker|source) ;;
        *) fail "--mode must be docker or source." ;;
    esac

    case "$TLS_MODE" in
        off|self-signed|manual|acme) ;;
        *) fail "--tls must be off, self-signed, manual, or acme." ;;
    esac

    case "$PORT" in
        ''|*[!0-9]*) fail "--port must be a number." ;;
    esac
    [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] \
        || fail "--port must be between 1 and 65535."

    case "$TLS_MODE" in
        self-signed|acme)
            [ -n "$TLS_DOMAIN" ] || fail "--domain is required for --tls $TLS_MODE."
            ;;
    esac
    if [ "$TLS_MODE" = "acme" ]; then
        [ -n "$TLS_EMAIL" ] || fail "--email is required for --tls acme."
    fi
}

absolute_directory() {
    target="$1"
    mkdir -p "$target" || fail "Cannot create $target."
    ( cd "$target" && pwd -P )
}

block_internal() {
    if [ "$ALLOW_INTERNAL" = "true" ]; then
        printf 'false'
    else
        printf 'true'
    fi
}

secure_cookies() {
    if [ "$TLS_MODE" = "off" ]; then
        printf 'false'
    else
        printf 'true'
    fi
}

resolve_origins() {
    if [ "$TLS_MODE" = "off" ]; then
        printf 'http://localhost:%s,http://127.0.0.1:%s' "$PORT" "$PORT"
        return 0
    fi
    # Engine.IO validates the Origin header against CORS_ORIGINS, so the real
    # TLS hostname has to be listed or every browser connection is rejected.
    printf 'https://localhost:%s,https://127.0.0.1:%s' "$PORT" "$PORT"
    if [ -n "$TLS_DOMAIN" ]; then
        printf ',https://%s:%s' "$TLS_DOMAIN" "$PORT"
        if [ "$PORT" = "443" ]; then
            printf ',https://%s' "$TLS_DOMAIN"
        fi
    fi
}

write_env_file() {
    env_file="$1"
    secret="$2"

    umask 077
    {
        printf '%s\n' "# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s\n' "SECRET_KEY=$secret"
        printf '%s\n' "DEPLOYMENT_PROFILE=homelab"
        printf '%s\n' "CORS_ORIGINS=$(resolve_origins)"
        printf '%s\n' "ALLOW_CORS_WILDCARD=false"
        printf '%s\n' "BLOCK_INTERNAL_SSH=$(block_internal)"
        printf '%s\n' "WEBSSH_TLS_MODE=$TLS_MODE"
        if [ -n "$TLS_DOMAIN" ]; then
            printf '%s\n' "WEBSSH_TLS_DOMAIN=$TLS_DOMAIN"
        fi
        if [ -n "$TLS_EMAIL" ]; then
            printf '%s\n' "WEBSSH_TLS_EMAIL=$TLS_EMAIL"
        fi
    } > "$env_file"
    chmod 600 "$env_file" 2>/dev/null || true
}

read_existing_secret() {
    env_file="$1"
    [ -f "$env_file" ] || return 1
    value="$(sed -n 's/^SECRET_KEY=//p' "$env_file" | head -n 1)"
    [ -n "$value" ] || return 1
    case "$value" in
        changeme|secret|your-secret-key|"<your-secret-key>")
            return 1
            ;;
    esac
    printf '%s' "$value"
}

write_compose_file() {
    compose_file="$1"

    umask 077
    {
        printf '%s\n' "# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s\n' "# Edit .env, then run: docker compose up -d"
        printf '%s\n' ''
        printf '%s\n' 'services:'
        printf '%s\n' '  webssh:'
        printf '%s\n' "    image: $IMAGE"
        printf '%s\n' '    container_name: webssh'
        printf '%s\n' '    restart: unless-stopped'
        printf '%s\n' '    stop_grace_period: 40s'
        printf '%s\n' '    env_file:'
        printf '%s\n' '      - .env'
        printf '%s\n' '    environment:'
        printf '%s\n' '      - PORT=5000'
        printf '%s\n' '      - TRUSTED_PROXIES=0'
        printf '%s\n' "      - SESSION_COOKIE_SECURE=$(secure_cookies)"
        printf '%s\n' '      - TMUX_ENABLED=true'
        printf '%s\n' '      - TMUX_DEFAULT=true'
        printf '%s\n' '      - TMUX_SESSION_PREFIX=webssh'
        printf '%s\n' '      - BACKUP_TEMP_DIR=/app/recovery'
        printf '%s\n' '      - BACKUP_RECOVERY_DURABLE=true'
        printf '%s\n' '    ports:'
        printf '%s\n' "      - \"$PORT:5000\""
        # The ACME standalone challenge needs host port 80. Skip it when the
        # chosen application port already binds 80, which would be a duplicate.
        if [ "$TLS_MODE" = "acme" ] && [ "$PORT" != "80" ]; then
            printf '%s\n' '      - "80:80"'
        fi
        printf '%s\n' '    volumes:'
        printf '%s\n' '      - webssh_data:/app/data'
        printf '%s\n' '      - webssh_recovery:/app/recovery'
        printf '%s\n' '    healthcheck:'
        printf '%s\n' '      test: ["CMD", "python", "healthcheck.py"]'
        printf '%s\n' '      interval: 30s'
        printf '%s\n' '      timeout: 5s'
        printf '%s\n' '      retries: 3'
        printf '%s\n' '      start_period: 10s'
        printf '%s\n' ''
        printf '%s\n' 'volumes:'
        printf '%s\n' '  webssh_data:'
        printf '%s\n' '  webssh_recovery:'
        printf '%s\n' '    driver: local'
    } > "$compose_file"
    chmod 600 "$compose_file" 2>/dev/null || true
}

wait_for_readiness() {
    base_url="$1"
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl is unavailable; skipping the readiness check."
        return 0
    fi
    elapsed=0
    while [ "$elapsed" -lt "$READY_TIMEOUT_SECONDS" ]; do
        if curl -fsSk --max-time 3 "$base_url/ready" >/dev/null 2>&1; then
            log "WebSSH is ready at $base_url"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    warn "The readiness endpoint did not answer within ${READY_TIMEOUT_SECONDS}s."
    warn "Inspect the service logs before exposing this instance."
    return 0
}

service_base_url() {
    if [ "$TLS_MODE" = "off" ]; then
        printf 'http://localhost:%s' "$PORT"
    else
        printf 'https://localhost:%s' "$PORT"
    fi
}

install_with_docker() {
    require_command docker "Docker is required for --mode docker."
    docker compose version >/dev/null 2>&1 \
        || fail "Docker Compose v2 is required (docker compose version failed)."

    env_file="$INSTALL_DIR/.env"
    secret="$(read_existing_secret "$env_file" || true)"
    if [ -z "$secret" ]; then
        secret="$(generate_secret)"
    fi
    write_env_file "$env_file" "$secret"
    write_compose_file "$INSTALL_DIR/docker-compose.yml"

    if [ "$START_SERVICE" != "true" ]; then
        log "Prepared $INSTALL_DIR (not started)."
        log "Start it later with: cd $INSTALL_DIR && docker compose up -d"
        return 0
    fi

    if [ "$PULL_IMAGE" = "true" ]; then
        log "Pulling the WebSSH image..."
        ( cd "$INSTALL_DIR" && docker compose pull --quiet ) \
            || warn "Image pull failed; continuing with any cached image."
    fi

    log "Starting WebSSH..."
    ( cd "$INSTALL_DIR" && docker compose up -d ) \
        || fail "docker compose up failed."

    wait_for_readiness "$(service_base_url)"
    log "Install directory: $INSTALL_DIR"
    log "Follow logs with: cd $INSTALL_DIR && docker compose logs -f"
}

install_from_source() {
    python_bin="$(python_command)"

    [ -f requirements.txt ] \
        || fail "Run install.sh from the WebSSH source checkout for --mode source."

    env_file="$INSTALL_DIR/.env"
    secret="$(read_existing_secret "$env_file" || true)"
    if [ -z "$secret" ]; then
        secret="$(generate_secret)"
    fi
    write_env_file "$env_file" "$secret"

    data_dir="$INSTALL_DIR/data"
    mkdir -p "$data_dir/logs" "$data_dir/keys"
    chmod 700 "$data_dir" "$data_dir/logs" "$data_dir/keys" 2>/dev/null || true

    if [ ! -x "$INSTALL_DIR/venv/bin/python" ]; then
        log "Creating the virtual environment..."
        "$python_bin" -m venv "$INSTALL_DIR/venv" \
            || fail "Could not create the virtual environment."
    fi
    venv_python="$INSTALL_DIR/venv/bin/python"

    log "Installing pinned dependencies..."
    "$venv_python" -m pip install --quiet --upgrade pip \
        || warn "pip upgrade failed; continuing."
    "$venv_python" -m pip install --quiet --require-hashes -r requirements.txt \
        || fail "Dependency installation failed."

    cert_dir="$data_dir/tls"
    case "$TLS_MODE" in
        self-signed)
            log "Generating a self-signed certificate for $TLS_DOMAIN..."
            mkdir -p "$cert_dir"
            # app.tls_certificates exits 2 after generating or rotating a
            # certificate and 0 when the existing one is still current.
            tls_status=0
            WEBSSH_TLS_MODE="$TLS_MODE" \
            WEBSSH_TLS_DOMAIN="$TLS_DOMAIN" \
            WEBSSH_TLS_CERT_DIR="$cert_dir" \
            SECRET_KEY="$secret" \
            DATA_DIR="$data_dir" \
                "$venv_python" -m app.tls_certificates \
                    --domain "$TLS_DOMAIN" --cert-dir "$cert_dir" \
                || tls_status=$?
            case "$tls_status" in
                0|2) ;;
                *)
                    fail "Self-signed certificate setup failed (exit $tls_status)."
                    ;;
            esac
            ;;
        manual)
            [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ] \
                || fail "Place fullchain.pem and privkey.pem in $cert_dir first."
            ;;
        acme)
            fail "ACME issuance needs the container image (port 80 reachable)."
            ;;
    esac

    if [ "$START_SERVICE" != "true" ]; then
        log "Prepared $INSTALL_DIR (not started)."
        return 0
    fi

    log "Starting WebSSH from the source checkout..."
    ( cd "$SOURCE_ROOT" && exec env \
        DATA_DIR="$data_dir" \
        SECRET_KEY="$secret" \
        HOST=0.0.0.0 \
        PORT="$PORT" \
        DEPLOYMENT_PROFILE=homelab \
        CORS_ORIGINS="$(resolve_origins)" \
        ALLOW_CORS_WILDCARD=false \
        BLOCK_INTERNAL_SSH="$(block_internal)" \
        WEBSSH_TLS_MODE="$TLS_MODE" \
        WEBSSH_TLS_DOMAIN="$TLS_DOMAIN" \
        WEBSSH_TLS_EMAIL="$TLS_EMAIL" \
        WEBSSH_TLS_CERT_DIR="$cert_dir" \
        "$venv_python" -m gunicorn \
            --worker-class gthread \
            --workers 1 \
            --threads 64 \
            --bind "0.0.0.0:$PORT" \
            start:app )
}

main() {
    parse_arguments "$@"

    log "$PROGRAM_NAME"
    log "Mode: $MODE | Port: $PORT | TLS: $TLS_MODE"

    SOURCE_ROOT="$(pwd -P)"
    INSTALL_DIR="$(absolute_directory "$INSTALL_DIR")"

    case "$MODE" in
        docker) install_with_docker ;;
        source) install_from_source ;;
    esac

    log "Done."
}

main "$@"
