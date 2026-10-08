#!/bin/sh
# WebSSH one-command installer and manager.
#
# Commands:
#   install         (default) install and start WebSSH
#   upgrade         pull the newest release and restart the service
#   port            change the published web port
#   reset-password  reset the password of a local account
#   status          show the service state and readiness
#   uninstall       stop and completely remove WebSSH
#
# Install modes:
#   docker  (default) - pull the published image and run it through Compose
#   source            - build a local virtualenv and run gunicorn directly
#
# The installer is idempotent: re-running it keeps the existing data
# directory, generated application secret, and TLS material.
#
# Usage:
#   ./install.sh [command] [options]
#
# Run `./install.sh --help` for the full option list.

set -eu

PROGRAM_NAME="WebSSH installer"
DEFAULT_PORT=5000
DEFAULT_DIR="./webssh-deployment"
IMAGE="ghcr.io/zhengwuji/web-ssh:latest"
READY_TIMEOUT_SECONDS=120
SERVICE_NAME="webssh"
SERVICE_FILE="/etc/systemd/system/webssh.service"
GUNICORN_THREADS=64

COMMAND="install"
MODE="docker"
INSTALL_DIR="$DEFAULT_DIR"
PORT="$DEFAULT_PORT"
PORT_SET="false"
TLS_MODE="off"
TLS_DOMAIN=""
TLS_EMAIL=""
START_SERVICE="true"
ALLOW_INTERNAL="false"
PULL_IMAGE="true"
SKIP_SYSTEM_DEPS="false"
INSTALL_DOCKER="auto"
RESET_USERNAME=""
PASSWORD_FILE=""
GENERATE_PASSWORD="false"
PURGE="false"
ASSUME_YES="false"
SOURCE_ROOT=""
ENV_FILE=""
SERVICE_ENV_FILE=""
RESOLVED_MODE=""
RUNTIME_USER=""
PYTHON_BIN=""
REPO_URL=""
REPO_REF="main"

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
  ./install.sh [command] [options]

Commands:
  install           Install and start WebSSH (default command)
  upgrade           Update to the newest release and restart the service
  port              Change the published web port
  reset-password    Reset the password of a local account
  status            Show the service state and the readiness probe
  uninstall         Stop the service and remove the installation
  help              Show this message

Install options:
  --mode docker|source   Install mode. Default: docker
  --dir PATH             Install directory. Default: ./webssh-deployment
  --port PORT            Published port. Default: 5000
  --tls MODE             off | self-signed | manual | acme. Default: off
  --domain NAME          TLS domain or IP. Required for self-signed and acme
  --email ADDRESS        ACME account email. Required for acme
  --allow-internal-ssh   Allow SSH connections to loopback and private targets
  --no-start             Prepare files only; do not start the service
  --no-pull              Skip the image pull step (docker mode)
  --skip-system-deps     Do not install missing OS packages
  --install-docker       Install Docker when it is missing (docker mode)
  --no-install-docker    Never install Docker; fail instead

Source mode also accepts:
  --from-git URL         Clone the repository from this URL instead of
                         requiring a local checkout (use this with `curl | sh`)
  --ref REF              Git branch, tag, or commit for --from-git.

Command options:
  --username NAME        Account name for reset-password
  --password-file PATH   Read the new password from this file
  --generate             Generate a random password and print it once
  --purge                Remove application data too (uninstall)
  --yes                  Do not ask for confirmation

Examples:
  curl -fsSL https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.sh | sh
  ./install.sh --mode docker --port 8443 --tls self-signed --domain webssh.lan
  ./install.sh port --port 9000
  ./install.sh reset-password --username admin
  ./install.sh uninstall --purge --yes

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
    return 1
}

# ---------------------------------------------------------------------------
# Operating system support
# ---------------------------------------------------------------------------

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        printf 'apt'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf'
    elif command -v yum >/dev/null 2>&1; then
        printf 'yum'
    elif command -v zypper >/dev/null 2>&1; then
        printf 'zypper'
    elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman'
    elif command -v apk >/dev/null 2>&1; then
        printf 'apk'
    else
        printf 'unknown'
    fi
}

distribution_name() {
    if [ -r /etc/os-release ]; then
        name="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release | head -n 1)"
        if [ -n "$name" ]; then
            printf '%s' "$name"
            return 0
        fi
    fi
    printf '%s' "$(uname -s)"
}

run_privileged() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
        return $?
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi
    return 1
}

package_install() {
    manager="$(detect_package_manager)"
    case "$manager" in
        apt)
            run_privileged env DEBIAN_FRONTEND=noninteractive apt-get update -qq
            run_privileged env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends "$@"
            ;;
        dnf) run_privileged dnf install -y "$@" ;;
        yum) run_privileged yum install -y "$@" ;;
        zypper) run_privileged zypper --non-interactive install "$@" ;;
        pacman) run_privileged pacman -Sy --noconfirm "$@" ;;
        apk) run_privileged apk add --no-cache "$@" ;;
        *) return 1 ;;
    esac
}

# Package names differ per distribution, so each dependency lists one spelling
# per supported package manager.
install_package_set() {
    manager="$(detect_package_manager)"
    case "$1" in
        python)
            case "$manager" in
                apt) package_install python3 python3-venv python3-pip ;;
                dnf|yum) package_install python3 python3-pip ;;
                zypper) package_install python3 python3-pip ;;
                pacman) package_install python python-pip ;;
                apk) package_install python3 py3-pip py3-virtualenv ;;
            esac
            ;;
        pip)
            case "$manager" in
                apt) package_install python3-pip python3-venv ;;
                dnf|yum) package_install python3-pip ;;
                zypper) package_install python3-pip ;;
                pacman) package_install python-pip ;;
                apk) package_install py3-pip ;;
            esac
            ;;
        curl)
            case "$manager" in
                apt) package_install curl ;;
                *) package_install curl ;;
            esac
            ;;
        tmux)
            case "$manager" in
                apt) package_install tmux ;;
                dnf|yum) package_install tmux ;;
                zypper) package_install tmux ;;
                pacman) package_install tmux ;;
                apk) package_install tmux ;;
            esac
            ;;
        git)
            package_install git
            ;;
        ldap-build)
            # python-ldap (via bonsai) has no Linux wheel, so pip builds it from
            # source. That needs a C toolchain plus the OpenLDAP and SASL
            # headers and the interpreter headers of the Python in use.
            case "$manager" in
                apt) package_install build-essential python3-dev libldap2-dev libsasl2-dev ;;
                dnf|yum) package_install gcc gcc-c++ make python3-devel openldap-devel cyrus-sasl-devel ;;
                zypper) package_install gcc gcc-c++ make python3-devel openldap2-devel cyrus-sasl-devel ;;
                pacman) package_install base-devel libldap libsasl ;;
                apk) package_install build-base python3-dev openldap-dev cyrus-sasl-dev ;;
            esac
            ;;
        python-headers)
            case "$manager" in
                apt) package_install python3-dev ;;
                dnf|yum) package_install python3-devel ;;
                zypper) package_install python3-devel ;;
                pacman) package_install python ;;
                apk) package_install python3-dev ;;
            esac
            ;;
        make)
            case "$manager" in
                apt) package_install build-essential ;;
                dnf|yum) package_install gcc gcc-c++ make ;;
                zypper) package_install gcc gcc-c++ make ;;
                pacman) package_install base-devel ;;
                apk) package_install build-base ;;
            esac
            ;;
    esac
}

systemd_available() {
    command -v systemctl >/dev/null 2>&1 || return 1
    [ -d /run/systemd/system ] || return 1
    return 0
}

try_install_git() {
    [ "$SKIP_SYSTEM_DEPS" = "true" ] && return 1
    log "Installing git (needed to fetch the source checkout)..."
    install_package_set git >/dev/null 2>&1 || true
    command -v git >/dev/null 2>&1
}

ensure_optional_tools() {
    [ "$SKIP_SYSTEM_DEPS" = "true" ] && return 0
    if ! command -v curl >/dev/null 2>&1; then
        log "Installing curl (needed for the readiness check)..."
        install_package_set curl || warn "Could not install curl."
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        log "Installing tmux (required for persistent sessions)..."
        install_package_set tmux || warn "Could not install tmux; persistent sessions stay unavailable."
    fi
}

# `bonsai` (the LDAP client) has no Linux wheel, so pip compiles it from source.
ensure_ldap_build_dependencies() {
    [ "$SKIP_SYSTEM_DEPS" = "true" ] && return 0

    needs_toolchain="false"
    command -v cc >/dev/null 2>&1 || needs_toolchain="true"
    [ -f /usr/include/sasl/sasl.h ] || needs_toolchain="true"

    python_bin="${PYTHON_BIN:-}"
    needs_headers="false"
    if [ -n "$python_bin" ]; then
        "$python_bin" -c 'import os, sysconfig; raise SystemExit(0 if os.path.isfile(os.path.join(sysconfig.get_paths()["include"], "Python.h")) else 1)' \
            >/dev/null 2>&1 || needs_headers="true"
    fi

    if [ "$needs_headers" = "true" ]; then
        log "Installing Python development headers (needed to compile the LDAP client)..."
        install_package_set python-headers \
            || warn "Could not install the Python development headers."
    fi

    if [ "$needs_toolchain" = "true" ]; then
        log "Installing C build tools and OpenLDAP headers (needed to compile the LDAP client)..."
        install_package_set ldap-build \
            || warn "Could not install the LDAP build dependencies; dependency installation may fail."
    fi

    if [ -n "$python_bin" ] \
        && ! "$python_bin" -c 'import os, sysconfig; raise SystemExit(0 if os.path.isfile(os.path.join(sysconfig.get_paths()["include"], "Python.h")) else 1)' >/dev/null 2>&1; then
        fail "Python development headers are missing for $python_bin. Install the python3-dev (or the distribution equivalent) package and retry."
    fi
    if ! command -v cc >/dev/null 2>&1; then
        fail "A C compiler is required to build the LDAP client. Install build-essential (or the distribution equivalent) and retry."
    fi
}

ensure_python_runtime() {
    if [ "$SKIP_SYSTEM_DEPS" != "true" ]; then
        if ! python_command >/dev/null 2>&1; then
            log "Installing Python 3 (not found on $(distribution_name))..."
            install_package_set python || warn "Automatic Python installation failed."
        fi
    fi

    PYTHON_BIN="$(python_command || true)"
    if [ -z "$PYTHON_BIN" ]; then
        fail "Python 3.10 or newer is required for --mode source. Install it and retry, or use --mode docker."
    fi

    if [ "$SKIP_SYSTEM_DEPS" != "true" ]; then
        if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
            log "Installing pip and the venv module..."
            install_package_set pip || warn "Automatic pip installation failed."
        fi

        if ! "$PYTHON_BIN" -m venv --help >/dev/null 2>&1; then
            log "Installing the Python venv module..."
            install_package_set python || warn "Automatic venv installation failed."
        fi
    fi

    "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 \
        || fail "pip is unavailable for $PYTHON_BIN. Install python3-venv/python3-pip (or the distribution equivalent) and retry."
    "$PYTHON_BIN" -m venv --help >/dev/null 2>&1 \
        || fail "The venv module is unavailable for $PYTHON_BIN. Install python3-venv (or the distribution equivalent) and retry."
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        return 0
    fi

    if [ "$INSTALL_DOCKER" = "false" ]; then
        fail "Docker and Docker Compose v2 are required for docker mode (--no-install-docker was given)."
    fi

    if [ "$SKIP_SYSTEM_DEPS" = "true" ]; then
        fail "Docker is not installed. Install Docker Engine and the Compose plugin, or use --mode source."
    fi

    log "Docker was not found on $(distribution_name); installing it now..."
    case "$(detect_package_manager)" in
        apt) package_install docker.io docker-compose-v2 || package_install docker.io docker-compose-plugin || true ;;
        dnf|yum) package_install docker docker-compose-plugin || true ;;
        zypper) package_install docker docker-compose || true ;;
        pacman) package_install docker docker-compose || true ;;
        apk) package_install docker docker-cli-compose || true ;;
        *) warn "Unsupported package manager." ;;
    esac

    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        if command -v curl >/dev/null 2>&1; then
            log "Falling back to the official Docker convenience script..."
            curl -fsSL https://get.docker.com | run_privileged sh || true
        fi
    fi

    command -v docker >/dev/null 2>&1 \
        || fail "Docker could not be installed automatically. Install Docker Engine manually (https://docs.docker.com/engine/install/) and retry."

    if ! docker compose version >/dev/null 2>&1; then
        fail "Docker is installed but the Compose v2 plugin is missing. Install docker-compose-plugin and retry."
    fi

    if systemd_available; then
        run_privileged systemctl enable --now docker >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

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
                PORT_SET="true"
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
            --username)
                [ "$#" -ge 2 ] || fail "--username requires a value."
                RESET_USERNAME="$2"
                shift 2
                ;;
            --password-file)
                [ "$#" -ge 2 ] || fail "--password-file requires a value."
                PASSWORD_FILE="$2"
                shift 2
                ;;
            --from-git)
                [ "$#" -ge 2 ] || fail "--from-git requires a value."
                REPO_URL="$2"
                shift 2
                ;;
            --ref)
                [ "$#" -ge 2 ] || fail "--ref requires a value."
                REPO_REF="$2"
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
            --skip-system-deps)
                SKIP_SYSTEM_DEPS="true"
                shift
                ;;
            --install-docker)
                INSTALL_DOCKER="true"
                shift
                ;;
            --no-install-docker)
                INSTALL_DOCKER="false"
                shift
                ;;
            --generate)
                GENERATE_PASSWORD="true"
                shift
                ;;
            --purge)
                PURGE="true"
                shift
                ;;
            --yes|-y)
                ASSUME_YES="true"
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

    if [ "$GENERATE_PASSWORD" = "true" ] && [ -n "$PASSWORD_FILE" ]; then
        fail "--generate and --password-file cannot be combined."
    fi

    if [ "$COMMAND" != "reset-password" ]; then
        if [ -n "$RESET_USERNAME" ] || [ -n "$PASSWORD_FILE" ] || [ "$GENERATE_PASSWORD" = "true" ]; then
            fail "--username, --password-file, and --generate require the reset-password command."
        fi
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
        printf '%s\n' "# Published host port. The container always listens on 5000, so this"
        printf '%s\n' "# key is installer metadata and is not read by the application."
        printf '%s\n' "WEBSSH_HOST_PORT=$PORT"
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

write_service_env_file() {
    env_file="$1"
    secret="$2"
    data_dir="$3"

    umask 077
    {
        printf '%s\n' "# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s\n' "DATA_DIR=$data_dir"
        printf '%s\n' "HOST=0.0.0.0"
        printf '%s\n' "PORT=$PORT"
        printf '%s\n' "# Source checkout that owns the virtualenv and the systemd unit."
        printf '%s\n' "WEBSSH_SOURCE_ROOT=$SOURCE_ROOT"
        printf '%s\n' "SECRET_KEY=$secret"
        printf '%s\n' "DEPLOYMENT_PROFILE=homelab"
        printf '%s\n' "CORS_ORIGINS=$(resolve_origins)"
        printf '%s\n' "ALLOW_CORS_WILDCARD=false"
        printf '%s\n' "BLOCK_INTERNAL_SSH=$(block_internal)"
        printf '%s\n' "SESSION_COOKIE_SECURE=$(secure_cookies)"
        printf '%s\n' "WEBSSH_TLS_MODE=$TLS_MODE"
        printf '%s\n' "WEBSSH_TLS_CERT_DIR=$data_dir/tls"
        if [ -n "$TLS_DOMAIN" ]; then
            printf '%s\n' "WEBSSH_TLS_DOMAIN=$TLS_DOMAIN"
        fi
        if [ -n "$TLS_EMAIL" ]; then
            printf '%s\n' "WEBSSH_TLS_EMAIL=$TLS_EMAIL"
        fi
    } > "$env_file"
    chmod 600 "$env_file" 2>/dev/null || true
}

read_env_value() {
    file="$1"
    key="$2"
    [ -f "$file" ] || return 1
    value="$(sed -n "s/^${key}=//p" "$file" | head -n 1)"
    [ -n "$value" ] || return 1
    printf '%s' "$value"
}

read_existing_secret() {
    env_file="$1"
    value="$(read_env_value "$env_file" SECRET_KEY || true)"
    [ -n "$value" ] || return 1
    case "$value" in
        changeme|secret|your-secret-key|"<your-secret-key>")
            return 1
            ;;
    esac
    printf '%s' "$value"
}

# Reload the settings an existing deployment was created with, so `port`,
# `upgrade`, `status`, and `uninstall` act on the real configuration.
load_existing_config() {
    existing="$INSTALL_DIR/.env"
    [ -f "$existing" ] || existing="$INSTALL_DIR/service.env"
    [ -f "$existing" ] || return 0

    value="$(read_env_value "$existing" WEBSSH_TLS_MODE || true)"
    [ -n "$value" ] && TLS_MODE="$value"
    value="$(read_env_value "$existing" WEBSSH_TLS_DOMAIN || true)"
    [ -n "$value" ] && TLS_DOMAIN="$value"
    value="$(read_env_value "$existing" WEBSSH_TLS_EMAIL || true)"
    [ -n "$value" ] && TLS_EMAIL="$value"
    value="$(read_env_value "$existing" BLOCK_INTERNAL_SSH || true)"
    if [ "$value" = "false" ]; then
        ALLOW_INTERNAL="true"
    fi
    if [ "$PORT_SET" != "true" ]; then
        value="$(read_env_value "$existing" WEBSSH_HOST_PORT || true)"
        [ -n "$value" ] || value="$(read_env_value "$existing" PORT || true)"
        [ -n "$value" ] && PORT="$value"
    fi
    value="$(read_env_value "$existing" WEBSSH_SOURCE_ROOT || true)"
    [ -n "$value" ] && SOURCE_ROOT="$value"
    return 0
}

detect_installed_mode() {
    if [ -f "$INSTALL_DIR/service.env" ] || [ -x "$INSTALL_DIR/venv/bin/python" ]; then
        printf 'source'
        return 0
    fi
    printf 'docker'
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

port_is_busy() {
    port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
        return $?
    fi
    return 1
}

# True when the running $SERVICE_NAME unit is the listener on $port. Anything
# else answering there means a restart would leave WebSSH unable to bind while
# `systemctl is-active` still reports success.
port_owned_by_service() {
    port="$1"
    command -v ss >/dev/null 2>&1 || return 1
    main_pid="$(run_privileged systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || true)"
    case "$main_pid" in
        ''|0) return 1 ;;
    esac
    listeners="$(ss -lntp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {print}')"
    [ -n "$listeners" ] || return 1
    printf '%s' "$listeners" | grep -q "pid=${main_pid}," && return 0
    return 1
}

ensure_port_available_for_service() {
    port="$1"
    port_is_busy "$port" || return 0
    if [ -f "$SERVICE_FILE" ] && port_owned_by_service "$port"; then
        return 0
    fi
    fail "Port $port is already in use by another process. Pick a different --port or stop that process first."
}

# A readiness probe alone cannot prove that WebSSH owns the port: another
# process may already answer there. Confirm the unit itself stayed up.
wait_for_service() {
    base_url="$1"
    elapsed=0
    while [ "$elapsed" -lt "$READY_TIMEOUT_SECONDS" ]; do
        if run_privileged systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
            wait_for_readiness "$base_url"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    warn "The $SERVICE_NAME service did not stay active."
    if command -v journalctl >/dev/null 2>&1; then
        warn "Recent logs:"
        run_privileged journalctl -u "$SERVICE_NAME" --no-pager -n 20 >&2 || true
    fi
    return 1
}

service_base_url() {
    if [ "$TLS_MODE" = "off" ]; then
        printf 'http://localhost:%s' "$PORT"
    else
        printf 'https://localhost:%s' "$PORT"
    fi
}

confirm_or_abort() {
    message="$1"
    if [ "$ASSUME_YES" = "true" ]; then
        return 0
    fi
    if [ -t 0 ]; then
        printf '%s [y/N] ' "$message"
        read -r reply || reply=""
        case "$reply" in
            y|Y|yes|YES) return 0 ;;
        esac
        return 1
    fi
    return 1
}

reuse_or_generate_secret() {
    env_file="$INSTALL_DIR/.env"
    secret="$(read_existing_secret "$env_file" || true)"
    if [ -z "$secret" ]; then
        for candidate in "$INSTALL_DIR/service.env"; do
            if [ -z "$secret" ]; then
                secret="$(read_existing_secret "$candidate" || true)"
            fi
        done
    fi
    if [ -z "$secret" ]; then
        secret="$(generate_secret)"
    fi
    printf '%s' "$secret"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

install_with_docker() {
    ensure_docker

    env_file="$INSTALL_DIR/.env"
    secret="$(reuse_or_generate_secret)"
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
    log "Change the port with: ./install.sh port --port PORT"
    log "Reset a password with: ./install.sh reset-password --username NAME"
}

install_source_certificates() {
    data_dir="$1"
    venv_python="$2"
    secret="$3"
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
}

gunicorn_tls_arguments() {
    case "$TLS_MODE" in
        off) printf '' ;;
        *) printf '%s' "--certfile=$1/fullchain.pem --keyfile=$1/privkey.pem" ;;
    esac
}

write_systemd_unit() {
    data_dir="$1"
    venv_python="$2"
    cert_dir="$data_dir/tls"
    tls_args="$(gunicorn_tls_arguments "$cert_dir")"
    exec_args="--worker-class gthread --workers 1 --threads $GUNICORN_THREADS --bind 0.0.0.0:$PORT"
    if [ -n "$tls_args" ]; then
        exec_args="$exec_args $tls_args"
    fi
    user_line=""
    if [ "$(id -u)" != "0" ]; then
        user_line="User=$(id -un)
"
    fi

    umask 022
    run_privileged mkdir -p "$(dirname "$SERVICE_FILE")"
    run_privileged sh -c "cat > '$SERVICE_FILE'" <<UNIT
[Unit]
Description=WebSSH web-based SSH client
Documentation=https://github.com/zhengwuji/web-ssh
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
${user_line}WorkingDirectory=$SOURCE_ROOT
EnvironmentFile=$SERVICE_ENV_FILE
ExecStart=$venv_python -m gunicorn $exec_args start:app
Restart=on-failure
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=40

[Install]
WantedBy=multi-user.target
UNIT
    run_privileged chmod 644 "$SERVICE_FILE"
}

install_from_source() {
    if [ ! -f requirements.txt ]; then
        if [ -z "$REPO_URL" ]; then
            fail "Run install.sh from the WebSSH source checkout, or pass --from-git URL (for example --from-git https://github.com/zhengwuji/web-ssh.git)."
        fi
        command -v git >/dev/null 2>&1 || {
            try_install_git
        }
        command -v git >/dev/null 2>&1 \
            || fail "git is required to clone the source checkout."
        checkout="$INSTALL_DIR/source"
        if [ -d "$checkout/.git" ]; then
            log "Updating the cloned checkout in $checkout..."
            ( cd "$checkout" && git fetch --depth 1 origin "$REPO_REF" && git checkout FETCH_HEAD ) \
                || fail "Could not update the cloned checkout."
        else
            log "Cloning $REPO_URL ($REPO_REF) into $checkout..."
            mkdir -p "$INSTALL_DIR"
            ( cd "$INSTALL_DIR" && git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" source ) \
                || fail "Could not clone $REPO_URL."
        fi
        SOURCE_ROOT="$checkout"
    fi

    [ -f "$SOURCE_ROOT/requirements.txt" ] \
        || fail "Run install.sh from the WebSSH source checkout for --mode source."

    ensure_python_runtime
    python_bin="$PYTHON_BIN"
    ensure_optional_tools
    ensure_ldap_build_dependencies

    secret="$(reuse_or_generate_secret)"
    write_env_file "$INSTALL_DIR/.env" "$secret"

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
    ( cd "$SOURCE_ROOT" && "$venv_python" -m pip install --quiet --require-hashes -r requirements.txt ) \
        || fail "Dependency installation failed."

    install_source_certificates "$data_dir" "$venv_python" "$secret"

    SERVICE_ENV_FILE="$INSTALL_DIR/service.env"
    write_service_env_file "$SERVICE_ENV_FILE" "$secret" "$data_dir"

    if [ "$START_SERVICE" != "true" ]; then
        log "Prepared $INSTALL_DIR (not started)."
        log "Start it later with: $venv_python -m gunicorn --worker-class gthread --workers 1 --threads $GUNICORN_THREADS --bind 0.0.0.0:$PORT start:app"
        return 0
    fi

    if systemd_available && run_privileged true 2>/dev/null; then
        ensure_port_available_for_service "$PORT"
        log "Installing the systemd service '$SERVICE_NAME'..."
        write_systemd_unit "$data_dir" "$venv_python"
        run_privileged systemctl daemon-reload || fail "systemctl daemon-reload failed."
        run_privileged systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
        run_privileged systemctl restart "$SERVICE_NAME" \
            || fail "Could not start the $SERVICE_NAME service. Inspect: systemctl status $SERVICE_NAME"
        wait_for_service "$(service_base_url)" \
            || fail "The $SERVICE_NAME service did not become ready on port $PORT."
        log "Service: $SERVICE_NAME (systemctl status $SERVICE_NAME)"
        log "Logs: journalctl -u $SERVICE_NAME -f"
        log "Change the port with: ./install.sh port --port PORT"
        log "Reset a password with: ./install.sh reset-password --username NAME"
        return 0
    fi

    # Without systemd the previous behaviour is preserved: run in the
    # foreground so the operator can stop it with Ctrl+C.
    warn "systemd is unavailable; starting WebSSH in the foreground."
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
        SESSION_COOKIE_SECURE="$(secure_cookies)" \
        WEBSSH_TLS_MODE="$TLS_MODE" \
        WEBSSH_TLS_DOMAIN="$TLS_DOMAIN" \
        WEBSSH_TLS_EMAIL="$TLS_EMAIL" \
        WEBSSH_TLS_CERT_DIR="$data_dir/tls" \
        "$venv_python" -m gunicorn \
            --worker-class gthread \
            --workers 1 \
            --threads "$GUNICORN_THREADS" \
            --bind "0.0.0.0:$PORT" \
            $(gunicorn_tls_arguments "$data_dir/tls") \
            start:app )
}

command_status() {
    log "$PROGRAM_NAME"
    log "Install directory: $INSTALL_DIR"
    log "Mode: $RESOLVED_MODE"
    log "Port: $PORT | TLS: $TLS_MODE"

    if [ "$RESOLVED_MODE" = "docker" ]; then
        if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
            if command -v docker >/dev/null 2>&1; then
                ( cd "$INSTALL_DIR" && docker compose ps ) || warn "docker compose ps failed."
            else
                warn "Docker is not installed; cannot inspect the containers."
            fi
        else
            log "No deployment found in $INSTALL_DIR."
            return 0
        fi
    else
        if systemd_available && [ -f "$SERVICE_FILE" ]; then
            run_privileged systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1 \
                && log "Service: $SERVICE_NAME is active"
            run_privileged systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1 \
                || warn "Service: $SERVICE_NAME is not active (systemctl status $SERVICE_NAME)"
        else
            warn "No systemd unit found for $SERVICE_NAME."
        fi
    fi

    if command -v curl >/dev/null 2>&1; then
        base_url="$(service_base_url)"
        if curl -fsSk --max-time 5 "$base_url/ready" >/dev/null 2>&1; then
            log "Readiness: $base_url/ready answered OK"
        else
            warn "Readiness: $base_url/ready did not answer."
        fi
    fi
}

command_port() {
    [ "$PORT_SET" = "true" ] || fail "--port is required for the port command."
    [ -d "$INSTALL_DIR" ] || fail "No deployment found in $INSTALL_DIR."

    log "Changing the WebSSH port to $PORT ($RESOLVED_MODE mode)..."

    if [ "$RESOLVED_MODE" = "docker" ]; then
        secret="$(reuse_or_generate_secret)"
        write_env_file "$INSTALL_DIR/.env" "$secret"
        write_compose_file "$INSTALL_DIR/docker-compose.yml"
        if [ "$START_SERVICE" = "true" ] && command -v docker >/dev/null 2>&1; then
            ( cd "$INSTALL_DIR" && docker compose up -d ) \
                || fail "docker compose up failed while changing the port."
            wait_for_readiness "$(service_base_url)"
        fi
    else
        secret="$(reuse_or_generate_secret)"
        write_env_file "$INSTALL_DIR/.env" "$secret"
        SERVICE_ENV_FILE="$INSTALL_DIR/service.env"
        write_service_env_file "$SERVICE_ENV_FILE" "$secret" "$INSTALL_DIR/data"
        if [ "$START_SERVICE" = "true" ] && systemd_available && [ -f "$SERVICE_FILE" ]; then
            ensure_port_available_for_service "$PORT"
            venv_python="$INSTALL_DIR/venv/bin/python"
            write_systemd_unit "$INSTALL_DIR/data" "$venv_python"
            run_privileged systemctl daemon-reload || fail "systemctl daemon-reload failed."
            run_privileged systemctl restart "$SERVICE_NAME" \
                || fail "Could not restart the $SERVICE_NAME service."
            wait_for_service "$(service_base_url)" \
                || fail "The $SERVICE_NAME service did not become ready on port $PORT."
        else
            log "Restart the service to apply the new port."
        fi
    fi

    log "WebSSH now listens on port $PORT."
}

command_reset_password() {
    [ -n "$RESET_USERNAME" ] || fail "--username is required for the reset-password command."
    [ -d "$INSTALL_DIR" ] || fail "No deployment found in $INSTALL_DIR."

    reset_flags=""
    if [ "$GENERATE_PASSWORD" = "true" ]; then
        reset_flags="--generate"
    fi

    if [ "$RESOLVED_MODE" = "docker" ]; then
        command -v docker >/dev/null 2>&1 \
            || fail "Docker is required to reset a password in docker mode."
        if [ -n "$PASSWORD_FILE" ]; then
            [ -f "$PASSWORD_FILE" ] || fail "Password file not found: $PASSWORD_FILE"
            ( cd "$INSTALL_DIR" && docker compose exec -T webssh \
                python -m flask --app start:app reset-password \
                --username "$RESET_USERNAME" --password-stdin \
                < "$PASSWORD_FILE" ) \
                || fail "Password reset failed."
        elif [ "$GENERATE_PASSWORD" = "true" ]; then
            ( cd "$INSTALL_DIR" && docker compose exec -T webssh \
                python -m flask --app start:app reset-password \
                --username "$RESET_USERNAME" --generate ) \
                || fail "Password reset failed."
        elif [ -t 0 ]; then
            ( cd "$INSTALL_DIR" && docker compose exec webssh \
                python -m flask --app start:app reset-password \
                --username "$RESET_USERNAME" ) \
                || fail "Password reset failed."
        else
            fail "Non-interactive shell: pass --password-file PATH or --generate."
        fi
        return 0
    fi

    venv_python="$INSTALL_DIR/venv/bin/python"
    [ -x "$venv_python" ] || fail "No source deployment found in $INSTALL_DIR."
    data_dir="$INSTALL_DIR/data"
    secret="$(reuse_or_generate_secret)"

    if [ -n "$PASSWORD_FILE" ]; then
        [ -f "$PASSWORD_FILE" ] || fail "Password file not found: $PASSWORD_FILE"
        reset_flags="--password-stdin"
    fi

    if [ "$GENERATE_PASSWORD" = "true" ]; then
        ( cd "$SOURCE_ROOT" && env DATA_DIR="$data_dir" SECRET_KEY="$secret" \
            "$venv_python" -m flask --app start:app reset-password \
            --username "$RESET_USERNAME" --generate ) \
            || fail "Password reset failed."
    elif [ -n "$PASSWORD_FILE" ]; then
        ( cd "$SOURCE_ROOT" && env DATA_DIR="$data_dir" SECRET_KEY="$secret" \
            "$venv_python" -m flask --app start:app reset-password \
            --username "$RESET_USERNAME" --password-stdin < "$PASSWORD_FILE" ) \
            || fail "Password reset failed."
    else
        ( cd "$SOURCE_ROOT" && env DATA_DIR="$data_dir" SECRET_KEY="$secret" \
            "$venv_python" -m flask --app start:app reset-password \
            --username "$RESET_USERNAME" ) \
            || fail "Password reset failed."
    fi
}

command_upgrade() {
    [ -d "$INSTALL_DIR" ] || fail "No deployment found in $INSTALL_DIR."

    if [ "$RESOLVED_MODE" = "docker" ]; then
        command -v docker >/dev/null 2>&1 || fail "Docker is required for docker mode."
        if [ "$PULL_IMAGE" = "true" ]; then
            log "Pulling the newest WebSSH image..."
            ( cd "$INSTALL_DIR" && docker compose pull --quiet ) \
                || fail "Image pull failed."
        fi
        ( cd "$INSTALL_DIR" && docker compose up -d ) \
            || fail "docker compose up failed."
        wait_for_readiness "$(service_base_url)"
    else
        if [ -d "$SOURCE_ROOT/.git" ] && command -v git >/dev/null 2>&1; then
            log "Updating the source checkout..."
            ( cd "$SOURCE_ROOT" && git pull --ff-only ) || warn "git pull failed; keeping the current revision."
        fi
        venv_python="$INSTALL_DIR/venv/bin/python"
        [ -x "$venv_python" ] || fail "No source deployment found in $INSTALL_DIR."
        if [ -f "$SOURCE_ROOT/requirements.txt" ]; then
            log "Reinstalling pinned dependencies..."
            ( cd "$SOURCE_ROOT" && "$venv_python" -m pip install --quiet --require-hashes -r requirements.txt ) \
                || fail "Dependency installation failed."
        fi
        if systemd_available && [ -f "$SERVICE_FILE" ]; then
            run_privileged systemctl restart "$SERVICE_NAME" \
                || fail "Could not restart the $SERVICE_NAME service."
            wait_for_readiness "$(service_base_url)"
        else
            log "Restart the service to apply the update."
        fi
    fi

    log "Upgrade finished."
}

command_uninstall() {
    [ -d "$INSTALL_DIR" ] || fail "No deployment found in $INSTALL_DIR."

    if [ "$PURGE" = "true" ]; then
        warn "This removes WebSSH and ALL application data in $INSTALL_DIR."
    fi
    confirm_or_abort "Remove WebSSH from $INSTALL_DIR (mode: $RESOLVED_MODE)?" \
        || fail "Aborted. Re-run with --yes to confirm in a non-interactive shell."

    if [ "$RESOLVED_MODE" = "docker" ]; then
        if command -v docker >/dev/null 2>&1 && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
            log "Stopping the containers..."
            if [ "$PURGE" = "true" ]; then
                ( cd "$INSTALL_DIR" && docker compose down -v ) \
                    || warn "docker compose down failed."
            else
                ( cd "$INSTALL_DIR" && docker compose down ) \
                    || warn "docker compose down failed."
            fi
        fi
    fi

    if [ -f "$SERVICE_FILE" ]; then
        log "Removing the systemd service..."
        if systemd_available; then
            run_privileged systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
        fi
        run_privileged rm -f "$SERVICE_FILE" || warn "Could not remove $SERVICE_FILE."
        if systemd_available; then
            run_privileged systemctl daemon-reload || true
            run_privileged systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
        fi
    fi

    log "Removing installation files..."
    rm -f "$INSTALL_DIR/docker-compose.yml" \
          "$INSTALL_DIR/service.env" \
          "$INSTALL_DIR/.env" || true
    if [ -d "$INSTALL_DIR/venv" ]; then
        rm -rf "$INSTALL_DIR/venv"
    fi
    if [ "$PURGE" = "true" ] && [ -d "$INSTALL_DIR/data" ]; then
        rm -rf "$INSTALL_DIR/data"
    fi

    if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        rmdir "$INSTALL_DIR" 2>/dev/null || true
    fi

    if [ "$PURGE" != "true" ]; then
        log "Application data kept in $INSTALL_DIR/data (use --purge to delete it)."
    fi
    log "WebSSH has been uninstalled."
}

main() {
    if [ "$#" -gt 0 ]; then
        case "$1" in
            install|upgrade|uninstall|port|reset-password|status|help)
                COMMAND="$1"
                shift
                ;;
            -*) ;;
            *)
                fail "Unknown command: $1 (run with --help)."
                ;;
        esac
    fi

    if [ "$COMMAND" = "help" ]; then
        usage
        exit 0
    fi

    parse_arguments "$@"

    log "$PROGRAM_NAME"
    log "Command: $COMMAND"

    SOURCE_ROOT="$(pwd -P)"
    INSTALL_DIR="$(absolute_directory "$INSTALL_DIR")"

    case "$COMMAND" in
        install)
            log "Mode: $MODE | Port: $PORT | TLS: $TLS_MODE"
            case "$MODE" in
                docker) install_with_docker ;;
                source) install_from_source ;;
            esac
            ;;
        status|upgrade|port|reset-password|uninstall)
            # Those commands act on an existing deployment, so resolve the
            # stored configuration before reporting or applying anything.
            load_existing_config
            RESOLVED_MODE="$(detect_installed_mode)"
            if [ "$COMMAND" != "status" ]; then
                log "Mode: $RESOLVED_MODE | Port: $PORT | TLS: $TLS_MODE"
            fi
            case "$COMMAND" in
                upgrade) command_upgrade ;;
                port) command_port ;;
                reset-password) command_reset_password ;;
                uninstall) command_uninstall ;;
                status) command_status ;;
            esac
            ;;
    esac

    log "Done."
}

main "$@"
