"""Container entrypoint persistence-boundary tests."""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

import pytest


ENTRYPOINT = Path(__file__).parents[1] / 'entrypoint.sh'


def _posix_shell():
    """Locate a real POSIX shell.

    A hardcoded ``/bin/bash`` is unavailable on Windows, and
    ``shutil.which('bash')`` there resolves to the WSL launcher stub
    (``C:\\WINDOWS\\system32\\bash.exe``), which exits 1 with no diagnostics.
    Prefer an explicit Git Bash path instead.
    """
    if os.name == 'nt':
        for candidate in (
            r'C:\Program Files\Git\bin\bash.exe',
            r'C:\Program Files (x86)\Git\bin\bash.exe',
        ):
            if Path(candidate).exists():
                return candidate
        return None
    return shutil.which('bash') or shutil.which('sh')


@pytest.fixture
def shell():
    found = _posix_shell()
    if found is None:
        pytest.skip('no POSIX shell available')
    return found


def _shell_path(path, shell):
    """Render a host path the way the POSIX shell sees it.

    Git Bash on Windows rejects a drive-letter path, so `G:\\data` has to reach
    the entrypoint as `/g/data`.
    """
    text = Path(path).as_posix()
    if os.name != 'nt' or not shell.lower().endswith('bash.exe'):
        return text
    if len(text) >= 2 and text[1] == ':':
        drive = text[0].lower()
        remainder = text[2:]
        if remainder.startswith('/'):
            remainder = remainder[1:]
        return f'/{drive}/{remainder}' if remainder else f'/{drive}'
    return text


def _shell_path_list(value, shell):
    """Translate a Windows PATH into the POSIX form the shell understands."""
    if os.name != 'nt' or not shell.lower().endswith('bash.exe'):
        return value
    entries = [entry for entry in value.split(os.pathsep) if entry.strip()]
    return ':'.join(_shell_path(entry, shell) for entry in entries)


def _entrypoint_command(shell, tmp_path, data_dir, command):
    """Build the argv that runs the entrypoint with a usable `python`.

    The entrypoint shells out to bare `python` for `os.path.realpath` and the
    generated secret. Git Bash rewrites PATH during startup and prepends its own
    `/usr/bin`, where a stub `python` shadows the real interpreter and prints
    nothing, leaving DATA_DIR empty. Setting PATH inside a wrapper script wins
    over that startup rewriting, so on Windows the entrypoint runs through one.
    """
    if os.name != 'nt' or not shell.lower().endswith('bash.exe'):
        return [shell, str(ENTRYPOINT), *command]

    wrapper = tmp_path / 'run-entrypoint.sh'
    wrapper.write_text(
        '#!/bin/bash\n'
        f'export PATH="{_shell_path(Path(sys.executable).parent, shell)}'
        ':/usr/bin:/bin"\n'
        f'exec "{_shell_path(ENTRYPOINT, shell)}" "$@"\n',
        encoding='utf-8',
        newline='\n',
    )
    return [shell, str(wrapper), *command]


def _run_entrypoint(shell, tmp_path, data_dir, *, secret=None):
    environment = {
        **os.environ,
        'DATA_DIR': _shell_path(data_dir, shell),
    }
    if secret is None:
        environment.pop('SECRET_KEY', None)
    else:
        environment['SECRET_KEY'] = secret
    return subprocess.run(
        _entrypoint_command(
            shell,
            tmp_path,
            data_dir,
            [
                sys.executable,
                '-c',
                (
                    'import os; '
                    'print(os.environ["DATA_DIR"]); '
                    'print(os.environ["SECRET_KEY"])'
                ),
            ],
        ),
        env=environment,
        text=True,
        encoding='utf-8',
        errors='replace',
        capture_output=True,
        check=False,
        timeout=120,
    )


def test_custom_data_dir_owns_generated_secret_and_runtime_directories(
        shell, tmp_path):
    data_dir = tmp_path / 'custom-data'

    result = _run_entrypoint(shell, tmp_path, data_dir)

    assert result.returncode == 0, result.stderr
    secret_file = data_dir / 'secret_key'
    secret = secret_file.read_text(encoding='utf-8').strip()
    assert len(secret) == 64
    assert result.stdout.splitlines()[-2:] == [str(data_dir.resolve()), secret]
    if os.name != 'nt':
        assert stat.S_IMODE(secret_file.stat().st_mode) == 0o600
    assert (data_dir / 'logs').is_dir()
    assert (data_dir / 'keys').is_dir()


def test_explicit_secret_wins_without_creating_a_split_secret_file(
        shell, tmp_path):
    data_dir = tmp_path / 'external-secret-data'

    result = _run_entrypoint(
        shell, tmp_path, data_dir, secret='external-secret-value'
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines()[-2:] == [
        str(data_dir.resolve()),
        'external-secret-value',
    ]
    assert not (data_dir / 'secret_key').exists()


def test_relative_data_dir_is_rejected_before_writing_state(shell, tmp_path):
    result = _run_entrypoint(shell, tmp_path, Path('relative-data'))

    assert result.returncode == 1
    assert result.stdout == ''
    assert 'DATA_DIR must be an absolute path' in result.stderr
