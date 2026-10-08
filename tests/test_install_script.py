"""Tests for the one-command installer (`install.sh`).

`tests/test_entrypoint.py` covers the container entrypoint and
`tests/test_tls_deployment.py` covers the deployed TLS surface. These cover the
host-side installer: its argument contract, the files it writes, idempotency,
and the exit-code contract it shares with `app.tls_certificates`.
"""

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).parents[1]
INSTALLER = PROJECT_ROOT / 'install.sh'


def _posix_shell():
    """Locate a real POSIX shell.

    On Windows `shutil.which('bash')` resolves to the WSL launcher stub
    (`C:\\WINDOWS\\system32\\bash.exe`), which exits 1 with no diagnostics and
    emits non-UTF-8 bytes. Prefer an explicit Git Bash path there.
    """
    if os.name == 'nt':
        for candidate in (
            r'C:\Program Files\Git\bin\bash.exe',
            r'C:\Program Files (x86)\Git\bin\bash.exe',
        ):
            if Path(candidate).exists():
                return candidate
        return None
    return shutil.which('sh') or shutil.which('bash')


@pytest.fixture
def shell():
    found = _posix_shell()
    if found is None:
        pytest.skip('no POSIX shell available')
    return found


def _write_executable(path, content):
    path.write_text(content, encoding='utf-8', newline='\n')
    path.chmod(
        path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    )


@pytest.fixture
def fake_bin(tmp_path):
    """A PATH entry holding deterministic `docker` and `python3` stand-ins."""
    directory = tmp_path / 'fake-bin'
    directory.mkdir()

    _write_executable(
        directory / 'docker',
        '#!/bin/sh\n'
        'case "$1 $2" in\n'
        '  "compose version") echo "Docker Compose version v2.29.0"; exit 0 ;;\n'
        'esac\n'
        'echo "fake docker: $*"\n'
        'exit 0\n',
    )

    _write_executable(
        directory / 'python3',
        '#!/bin/sh\n'
        'if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then\n'
        '  target="$3"\n'
        '  mkdir -p "$target/bin"\n'
        '  cat > "$target/bin/python" <<\'VENV_PYTHON\'\n'
        '#!/bin/sh\n'
        'if [ "$1" = "-m" ] && [ "$2" = "app.tls_certificates" ]; then\n'
        '  cert_dir=""\n'
        '  previous=""\n'
        '  for argument in "$@"; do\n'
        '    if [ "$previous" = "--cert-dir" ]; then cert_dir="$argument"; fi\n'
        '    previous="$argument"\n'
        '  done\n'
        '  mkdir -p "$cert_dir"\n'
        '  printf \'certificate\\n\' > "$cert_dir/fullchain.pem"\n'
        '  printf \'private key\\n\' > "$cert_dir/privkey.pem"\n'
        '  echo "TLS certificate generated/rotated"\n'
        '  exit 2\n'
        'fi\n'
        'exit 0\n'
        'VENV_PYTHON\n'
        '  chmod +x "$target/bin/python"\n'
        '  exit 0\n'
        'fi\n'
        'if [ "$1" = "-c" ]; then exit 0; fi\n'
        'exit 0\n',
    )

    _write_executable(
        directory / 'openssl',
        '#!/bin/sh\n'
        'echo "0123456789abcdef0123456789abcdef'
        '0123456789abcdef0123456789abcdef"\n',
    )

    return directory


def _run(shell, arguments, *, cwd, fake_bin=None, extra_path=''):
    path_entries = []
    if fake_bin is not None:
        path_entries.append(str(fake_bin).replace('\\', '/'))
    path_entries.extend(['/usr/bin', '/bin'])
    if extra_path:
        path_entries.append(extra_path)
    environment = {
        **os.environ,
        'PATH': ':'.join(path_entries),
        'LC_ALL': 'C',
    }
    return subprocess.run(
        [shell, str(INSTALLER), *arguments],
        cwd=str(cwd),
        env=environment,
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        check=False,
        timeout=120,
    )


def test_installer_parses_under_posix_shell(shell):
    result = subprocess.run(
        [shell, '-n', str(INSTALLER)],
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        check=False,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr


def test_installer_treats_the_first_run_rotation_as_success():
    """`python -m app.tls_certificates` exits 2 after generating a certificate.

    That is the normal outcome on a fresh deployment, so a bare
    `|| fail` aborted the source install exactly when no certificate existed.
    """
    script = INSTALLER.read_text(encoding='utf-8')

    assert 'tls_status=0' in script
    assert '0|2) ;;' in script
    assert 'fail "Self-signed certificate setup failed' in script


def test_help_documents_every_supported_mode(shell, tmp_path):
    result = _run(shell, ['--help'], cwd=tmp_path)

    assert result.returncode == 0
    assert '--mode docker|source' in result.stdout
    assert 'off | self-signed | manual | acme' in result.stdout
    assert '--allow-internal-ssh' in result.stdout


@pytest.mark.parametrize(
    'arguments, message',
    [
        (['--mode', 'bogus'], '--mode must be docker or source'),
        (['--port', 'abc'], '--port must be a number'),
        (['--port', '70000'], '--port must be between 1 and 65535'),
        (['--tls', 'bogus'], '--tls must be off, self-signed, manual, or acme'),
        (['--tls', 'self-signed'], '--domain is required for --tls self-signed'),
        (['--tls', 'acme', '--domain', 'ssh.example.com'], '--email is required'),
        (['--unknown-flag'], 'Unknown option: --unknown-flag'),
    ],
)
def test_invalid_arguments_are_rejected_before_writing_state(
        shell, tmp_path, arguments, message):
    target = tmp_path / 'never-created'

    result = _run(
        shell, ['--dir', str(target).replace('\\', '/'), *arguments],
        cwd=tmp_path,
    )

    assert result.returncode == 1
    assert message in result.stderr
    assert not target.exists()


def test_docker_install_writes_env_and_compose_then_stays_idempotent(
        shell, tmp_path, fake_bin):
    target = tmp_path / 'deployment'

    first = _run(
        shell,
        ['--dir', str(target).replace('\\', '/'), '--port', '5112', '--no-start'],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert first.returncode == 0, first.stderr

    env_file = target / '.env'
    compose_file = target / 'docker-compose.yml'
    assert env_file.is_file()
    assert compose_file.is_file()

    env_text = env_file.read_text(encoding='utf-8')
    secret_line = next(
        line for line in env_text.splitlines() if line.startswith('SECRET_KEY=')
    )
    secret = secret_line.split('=', 1)[1]
    assert len(secret) == 64
    assert 'CORS_ORIGINS=http://localhost:5112,http://127.0.0.1:5112' in env_text
    assert 'ALLOW_CORS_WILDCARD=false' in env_text
    assert 'BLOCK_INTERNAL_SSH=true' in env_text
    assert 'WEBSSH_TLS_MODE=off' in env_text

    compose_text = compose_file.read_text(encoding='utf-8')
    assert '- "5112:5000"' in compose_text
    assert 'env_file:' in compose_text
    assert 'webssh_data:/app/data' in compose_text

    if os.name != 'nt':
        assert stat.S_IMODE(env_file.stat().st_mode) == 0o600

    # A second run must reuse the generated secret instead of rotating it.
    second = _run(
        shell,
        ['--dir', str(target).replace('\\', '/'), '--port', '5112', '--no-start'],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert second.returncode == 0, second.stderr
    assert f'SECRET_KEY={secret}' in env_file.read_text(encoding='utf-8')


def test_tls_install_switches_origins_and_secure_cookies(
        shell, tmp_path, fake_bin):
    target = tmp_path / 'tls-deployment'

    result = _run(
        shell,
        [
            '--dir', str(target).replace('\\', '/'),
            '--port', '5443',
            '--tls', 'self-signed',
            '--domain', 'webssh.lan',
            '--no-start',
        ],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert result.returncode == 0, result.stderr

    env_text = (target / '.env').read_text(encoding='utf-8')
    assert 'CORS_ORIGINS=https://localhost:5443,https://127.0.0.1:5443' in env_text
    # Engine.IO validates the browser Origin, so the real TLS hostname must be
    # an accepted origin or every socket connection is refused.
    assert 'https://webssh.lan:5443' in env_text
    assert 'WEBSSH_TLS_MODE=self-signed' in env_text
    assert 'WEBSSH_TLS_DOMAIN=webssh.lan' in env_text

    compose_text = (target / 'docker-compose.yml').read_text(encoding='utf-8')
    assert 'SESSION_COOKIE_SECURE=true' in compose_text


def test_tls_origin_list_covers_the_implicit_default_port(
        shell, tmp_path, fake_bin):
    target = tmp_path / 'default-port-deployment'

    result = _run(
        shell,
        [
            '--dir', str(target).replace('\\', '/'),
            '--port', '443',
            '--tls', 'self-signed',
            '--domain', 'webssh.lan',
            '--no-start',
        ],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert result.returncode == 0, result.stderr

    env_text = (target / '.env').read_text(encoding='utf-8')
    # A browser omits :443, so the bare origin has to be accepted as well.
    assert 'https://webssh.lan:443' in env_text
    assert 'https://webssh.lan\n' in env_text


def test_acme_binds_the_challenge_port_once(shell, tmp_path, fake_bin):
    target = tmp_path / 'acme-deployment'

    result = _run(
        shell,
        [
            '--dir', str(target).replace('\\', '/'),
            '--port', '8443',
            '--tls', 'acme',
            '--domain', 'ssh.example.com',
            '--email', 'ops@example.com',
            '--no-start',
        ],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert result.returncode == 0, result.stderr

    compose_text = (target / 'docker-compose.yml').read_text(encoding='utf-8')
    assert '- "8443:5000"' in compose_text
    assert '- "80:80"' in compose_text

    # Publishing the application on port 80 already satisfies the ACME
    # challenge, so a second 80 binding would be a duplicate mapping.
    on_80 = tmp_path / 'acme-on-80'
    result = _run(
        shell,
        [
            '--dir', str(on_80).replace('\\', '/'),
            '--port', '80',
            '--tls', 'acme',
            '--domain', 'ssh.example.com',
            '--email', 'ops@example.com',
            '--no-start',
        ],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert result.returncode == 0, result.stderr

    compose_text = (on_80 / 'docker-compose.yml').read_text(encoding='utf-8')
    assert '- "80:5000"' in compose_text
    assert '- "80:80"' not in compose_text


def test_allow_internal_ssh_opts_out_of_target_blocking(
        shell, tmp_path, fake_bin):
    target = tmp_path / 'internal-deployment'

    result = _run(
        shell,
        [
            '--dir', str(target).replace('\\', '/'),
            '--allow-internal-ssh',
            '--no-start',
        ],
        cwd=tmp_path,
        fake_bin=fake_bin,
    )
    assert result.returncode == 0, result.stderr

    env_text = (target / '.env').read_text(encoding='utf-8')
    assert 'BLOCK_INTERNAL_SSH=false' in env_text


def test_source_install_requires_a_source_checkout(shell, tmp_path, fake_bin):
    outside = tmp_path / 'not-a-checkout'
    outside.mkdir()
    target = tmp_path / 'source-deployment'

    result = _run(
        shell,
        [
            '--mode', 'source',
            '--dir', str(target).replace('\\', '/'),
            '--no-start',
        ],
        cwd=outside,
        fake_bin=fake_bin,
    )

    assert result.returncode == 1
    assert 'source checkout' in result.stderr
