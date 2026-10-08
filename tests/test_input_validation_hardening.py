"""Regression tests for anchored-regex input validation.

`re.match(r'^...$', value)` accepts a trailing newline because `$` also matches
just before a final newline. Validators that did not `.strip()` first therefore
accepted `"alice\\n"`. Every validator in the project now uses `re.fullmatch`
(or an equivalent compiled pattern), which does not.
"""

import pytest

from app import jump_host_manager, profile_manager
from app.socket_events import (
    _TMUX_SESSION_NAME,
    _USERNAME_PATTERN as SOCKET_USERNAME_PATTERN,
    _validate_ssh_params,
)

USERNAME_PATTERNS = {
    'socket_events': SOCKET_USERNAME_PATTERN,
    'profile_manager': profile_manager._USERNAME_PATTERN,
    'jump_host_manager': jump_host_manager._USERNAME_PATTERN,
}

HOSTNAME_PATTERNS = {
    'profile_manager': profile_manager._HOSTNAME_PATTERN,
    'jump_host_manager': jump_host_manager._HOSTNAME_PATTERN,
}


@pytest.mark.parametrize('name', sorted(USERNAME_PATTERNS))
@pytest.mark.parametrize('value', ['alice\n', 'a\n', 'root\n', 'alice\r\n'])
def test_username_patterns_reject_trailing_newlines(name, value):
    assert USERNAME_PATTERNS[name].fullmatch(value) is None


@pytest.mark.parametrize('name', sorted(USERNAME_PATTERNS))
@pytest.mark.parametrize('value', ['alice', 'a', 'root', 'deploy_user', 'u.v-1'])
def test_username_patterns_accept_valid_names(name, value):
    assert USERNAME_PATTERNS[name].fullmatch(value) is not None


@pytest.mark.parametrize('name', sorted(HOSTNAME_PATTERNS))
@pytest.mark.parametrize('value', ['example.com\n', 'a\n', 'localhost\n'])
def test_hostname_patterns_reject_trailing_newlines(name, value):
    assert HOSTNAME_PATTERNS[name].fullmatch(value) is None


@pytest.mark.parametrize('name', sorted(HOSTNAME_PATTERNS))
@pytest.mark.parametrize('value', ['example.com', 'a', 'localhost', 'sub.example.co.uk'])
def test_hostname_patterns_accept_valid_hostnames(name, value):
    assert HOSTNAME_PATTERNS[name].fullmatch(value) is not None


@pytest.mark.parametrize('name', sorted(HOSTNAME_PATTERNS))
@pytest.mark.parametrize('value', ['-bad.example', 'bad-.example', 'a..b', 'a' * 64])
def test_hostname_patterns_reject_malformed_hostnames(name, value):
    assert HOSTNAME_PATTERNS[name].fullmatch(value) is None


@pytest.mark.parametrize('name', ['webssh_alpha\n', 'x\n', 'webssh_alpha\r\n'])
def test_tmux_session_names_reject_trailing_newlines(name):
    assert _TMUX_SESSION_NAME.fullmatch(name) is None


@pytest.mark.parametrize('name', ['webssh_alpha', 'session_1', 'x'])
def test_tmux_session_names_accept_valid_names(name):
    assert _TMUX_SESSION_NAME.fullmatch(name) is not None


def test_ssh_username_validation_rejects_an_embedded_newline():
    assert _validate_ssh_params('example.com', 22, 'alice\nfoo') == (
        None, None, None, 'Invalid username format',
    )


def test_ssh_username_validation_still_trims_surrounding_whitespace():
    """Surrounding whitespace is normalised before validation, by design."""
    assert _validate_ssh_params('example.com', 22, ' alice ') == (
        'example.com', 22, 'alice', None,
    )
    assert _validate_ssh_params('example.com', 22, 'alice\n') == (
        'example.com', 22, 'alice', None,
    )


def test_ssh_host_validation_rejects_an_embedded_newline():
    assert _validate_ssh_params('exam\nple.com', 22, 'alice') == (
        None, None, None, 'Invalid host format',
    )
