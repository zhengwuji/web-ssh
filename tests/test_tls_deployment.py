"""TLS acceptance tests for the deployment surface.

`tests/test_tls_certificates.py` covers certificate generation. These cover the
parts that only fail in a real deployment: the container entrypoint's exit-code
contract, the health probe's scheme switch, and a live HTTPS listener.
"""

import http.server
import os
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from app import tls_certificates

PROJECT_ROOT = Path(__file__).parents[1]
HEALTHCHECK = PROJECT_ROOT / 'healthcheck.py'
ENTRYPOINT = PROJECT_ROOT / 'entrypoint.sh'


def _free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


class _ReadyHandler(http.server.BaseHTTPRequestHandler):
    """Minimal stand-in for the app's /ready endpoint."""

    def do_GET(self):  # noqa: N802 - http.server API
        if self.path != '/ready':
            self.send_error(404)
            return
        body = b'{"status":"ready"}'
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # silence the test run
        return


class _TlsServer:
    def __init__(self, cert_file, key_file):
        self.port = _free_port()
        self.httpd = http.server.ThreadingHTTPServer(
            ('127.0.0.1', self.port), _ReadyHandler
        )
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert_file), str(key_file))
        self.httpd.socket = context.wrap_socket(
            self.httpd.socket, server_side=True
        )
        self.thread = threading.Thread(
            target=self.httpd.serve_forever, daemon=True
        )

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc_info):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)
        return False


def _run_healthcheck(port, mode):
    env = {**os.environ, 'PORT': str(port), 'WEBSSH_TLS_MODE': mode}
    return subprocess.run(
        [sys.executable, str(HEALTHCHECK)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )


@pytest.fixture
def self_signed(tmp_path):
    cert_file = tmp_path / 'fullchain.pem'
    key_file = tmp_path / 'privkey.pem'
    tls_certificates.generate_self_signed('127.0.0.1', cert_file, key_file)
    return cert_file, key_file


def test_entrypoint_treats_the_first_run_rotation_as_success():
    """`python -m app.tls_certificates` exits 2 after generating a certificate.

    That is the normal outcome on every fresh deployment, so `|| exit 1`
    aborted container startup exactly when no certificate existed yet.
    """
    script = ENTRYPOINT.read_text(encoding='utf-8')

    assert '_tls_status=$?' in script
    assert '0|2) ;;' in script
    assert 'exit 1' in script.split('_tls_status=$?', 1)[1]


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


def test_entrypoint_script_parses_under_posix_shell():
    """`sh -n` catches quoting regressions in the TLS branches."""
    shell = _posix_shell()
    if shell is None:
        pytest.skip('no POSIX shell available')
    result = subprocess.run(
        [shell, '-n', str(ENTRYPOINT)],
        capture_output=True,
        text=True,
        encoding='utf-8',
        errors='replace',
        check=False,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr


def test_healthcheck_uses_https_when_tls_is_enabled(self_signed):
    cert_file, key_file = self_signed

    with _TlsServer(cert_file, key_file) as server:
        https_result = _run_healthcheck(server.port, 'self-signed')
        assert https_result.returncode == 0, https_result.stderr

        # The plain-HTTP branch must not silently succeed against a TLS port.
        plain_result = _run_healthcheck(server.port, 'off')
        assert plain_result.returncode != 0


def test_healthcheck_reports_failure_when_nothing_listens():
    result = _run_healthcheck(_free_port(), 'self-signed')
    assert result.returncode != 0


def test_generated_certificate_serves_a_verified_tls_handshake(self_signed):
    """The self-signed certificate must be usable as its own trust anchor."""
    cert_file, key_file = self_signed

    with _TlsServer(cert_file, key_file) as server:
        context = ssl.create_default_context(cafile=str(cert_file))
        context.check_hostname = True
        with urllib.request.urlopen(
            f'https://127.0.0.1:{server.port}/ready',
            timeout=10,
            context=context,
        ) as response:
            assert response.status == 200
            assert response.read() == b'{"status":"ready"}'


def test_tls_port_rejects_a_plain_http_client(self_signed):
    cert_file, key_file = self_signed

    with _TlsServer(cert_file, key_file) as server:
        with pytest.raises((urllib.error.URLError, OSError)):
            urllib.request.urlopen(
                f'http://127.0.0.1:{server.port}/ready', timeout=5
            )
