"""Host-key confirmation coverage for the Quick (SFTP) connect socket flow.

Quick connect used to reach the pool with the historical silent
trust-on-first-use behaviour. It now asks the same first-seen host-key
question as an ordinary SSH connection, from a background job so that the
serialized socket handler never blocks on the answer.
"""
import threading
import time
from threading import Event

import pytest


pytestmark = pytest.mark.usefixtures('direct_socket_authentication')


def _socket_user(app, username):
    from app.auth import register_socket_session, register_user
    from app.models import db

    with app.app_context():
        user, error = register_user(username, 'socket-password-123')
        assert error is None
        sid = f'{username}-sid'
        register_socket_session(user.id, sid)
        db.session.commit()
        return user.id, sid


def _quick_payload(**overrides):
    value = {
        'host': 'target.example',
        'port': 22,
        'username': 'deploy',
        'password': 'Quick-Secret-42!',
    }
    value.update(overrides)
    return value


def _call(app, sid, handler, payload):
    from flask import request

    with app.test_request_context('/socket.io'):
        request.sid = sid
        return handler(payload)


def _answer_host_key_prompt(app, sid, prompt_id, accepted):
    from flask import request
    import app.socket_events as socket_events

    with app.test_request_context('/socket.io'):
        request.sid = sid
        return socket_events.handle_ssh_host_key_decision({
            'prompt_id': prompt_id,
            'accepted': accepted,
        })


def _wait_for(entries, event_name, timeout=5):
    """Poll a captured emit log until ``event_name`` shows up."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for entry in list(entries):
            if entry[0] == event_name:
                return entry
        time.sleep(0.01)
    raise AssertionError(f'{event_name} was never emitted: {entries!r}')


def _wait_for_prompt(prompts, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if prompts:
            return prompts[0]
        time.sleep(0.01)
    raise AssertionError(f'the host-key prompt was never emitted: {prompts!r}')


def _run_job_in_thread(app, job, cancel_event):
    def _run():
        with app.app_context():
            job(cancel_event)

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
    return thread


class _Handle:
    def __init__(self, cancel_event):
        self.cancel_event = cancel_event

    def cancel(self):
        self.cancel_event.set()
        return True


class _CapturedLifecycle:
    def __init__(self):
        self.jobs = []

    def accepting_work(self):
        return True

    def start_job(self, name, target, **kwargs):
        event = Event()
        handle = _Handle(event)
        self.jobs.append((name, target, event, kwargs))
        return handle


def _prepare_quick(app, monkeypatch, username, confirm_enabled=True):
    """Run one Quick connect handler call that parks its work in a fake lifecycle."""
    import app.socket_events as socket_events

    _user_id, sid = _socket_user(app, username)
    lifecycle = _CapturedLifecycle()
    app.extensions['runtime_lifecycle'] = lifecycle
    monkeypatch.setattr(
        socket_events.config, 'HOST_KEY_CONFIRM_ENABLED', confirm_enabled,
    )
    monkeypatch.setattr(socket_events, 'check_socket_rate_limit', lambda *_a: False)
    # The fake pool below never registers a live handle, so the descriptor
    # lookup is stubbed rather than exercised through the real resolver.
    monkeypatch.setattr(
        socket_events,
        '_public_file_source',
        lambda source_id, user_id: {
            'source_id': source_id,
            'kind': 'sftp-quick',
            'owner_id': user_id,
        },
    )

    sync_emitted = []
    monkeypatch.setattr(
        socket_events,
        'emit',
        lambda name, data=None, **_kwargs: sync_emitted.append((name, data)),
    )

    emitted = []

    def _emit(name, data=None, **kwargs):
        emitted.append((name, data, kwargs))

    monkeypatch.setattr(socket_events.socketio, 'emit', _emit)

    _call(app, sid, socket_events.handle_quick_connect, _quick_payload())

    # The handler must hand the network work to the lifecycle without blocking
    # on a host-key answer and without emitting anything itself.
    assert sync_emitted == []
    assert len(lifecycle.jobs) == 1
    assert lifecycle.jobs[0][0] == 'quick_connect'
    return socket_events, lifecycle, emitted, sid


def test_accepted_first_seen_key_creates_the_quick_connection(app, monkeypatch):
    from app import connection_pool

    socket_events, lifecycle, emitted, sid = _prepare_quick(
        app, monkeypatch, 'quick_host_key_accept',
    )
    decisions = []

    class _Pool:
        def create_connection(self, **kwargs):
            assert kwargs['user_id'].isdigit()
            assert kwargs['password'] == 'Quick-Secret-42!'
            decisions.append(kwargs['host_key_decision'](
                'target.example', 'ssh-ed25519', 'aa:bb:cc', 'target',
            ))
            return 'conn-quick-1', None

        def request_close(self, *_args):
            raise AssertionError('an accepted quick connection must stay open')

    monkeypatch.setattr(
        connection_pool.temp_connection_pool, 'create_connection',
        _Pool().create_connection,
    )

    thread = _run_job_in_thread(app, lifecycle.jobs[0][1], lifecycle.jobs[0][2])
    prompt = _wait_for(emitted, 'ssh_host_key_confirm')

    assert prompt[1] == {
        'prompt_id': prompt[1]['prompt_id'],
        'host': 'target.example',
        'port': 22,
        'key_type': 'ssh-ed25519',
        'fingerprint': 'aa:bb:cc',
        'context': 'target',
        'client_request_id': None,
        'flow': 'quick',
    }
    assert prompt[2]['room'] == sid
    assert 'Quick-Secret-42!' not in repr(emitted)

    assert _answer_host_key_prompt(
        app, sid, prompt[1]['prompt_id'], True,
    ) == {'success': True}
    thread.join(5)
    assert not thread.is_alive()
    assert decisions == [True]
    assert socket_events._ssh_host_key_prompts == {}

    assert emitted[-1][0] == 'quick_connect_success'
    assert emitted[-1][1]['connection_id'] == 'conn-quick-1'
    assert emitted[-1][2]['room'] == sid


def test_declined_first_seen_key_reports_the_unconfirmed_code(app, monkeypatch):
    from app import connection_pool
    from app.ssh_errors import SSHConnectionError

    socket_events, lifecycle, emitted, sid = _prepare_quick(
        app, monkeypatch, 'quick_host_key_decline',
    )
    decisions = []

    class _Pool:
        def create_connection(self, **kwargs):
            decisions.append(kwargs['host_key_decision'](
                'target.example', 'ssh-rsa', 'dd:ee:ff', 'target',
            ))
            return None, SSHConnectionError(
                'SSH host key is not trusted yet',
                code='host_key_unconfirmed',
                context='target',
            )

    monkeypatch.setattr(
        connection_pool.temp_connection_pool, 'create_connection',
        _Pool().create_connection,
    )

    thread = _run_job_in_thread(app, lifecycle.jobs[0][1], lifecycle.jobs[0][2])
    prompt = _wait_for(emitted, 'ssh_host_key_confirm')

    assert _answer_host_key_prompt(
        app, sid, prompt[1]['prompt_id'], False,
    ) == {'success': True}
    thread.join(5)
    assert not thread.is_alive()
    assert decisions == [False]
    assert socket_events._ssh_host_key_prompts == {}

    assert emitted[-1] == (
        'quick_connect_error',
        {
            'error': 'SSH host key is not trusted yet',
            'code': 'host_key_unconfirmed',
            'context': 'target',
        },
        {'room': sid},
    )


def test_confirm_disabled_keeps_the_historical_silent_trust(app, monkeypatch):
    from app import connection_pool

    _socket_events, lifecycle, emitted, sid = _prepare_quick(
        app, monkeypatch, 'quick_host_key_disabled', confirm_enabled=False,
    )
    observed = []

    class _Pool:
        def create_connection(self, **kwargs):
            observed.append(kwargs['host_key_decision'])
            return 'conn-quiet-1', None

    monkeypatch.setattr(
        connection_pool.temp_connection_pool, 'create_connection',
        _Pool().create_connection,
    )

    thread = _run_job_in_thread(app, lifecycle.jobs[0][1], lifecycle.jobs[0][2])
    thread.join(5)

    assert not thread.is_alive()
    assert observed == [None]
    assert [entry[0] for entry in emitted] == ['quick_connect_success']
    assert emitted[0][1]['connection_id'] == 'conn-quiet-1'
    assert emitted[0][2]['room'] == sid


def test_a_prompt_without_a_request_id_is_woken_by_a_none_cancel(app, monkeypatch):
    import app.socket_events as socket_events

    user_id, sid = _socket_user(app, 'quick_prompt_cancel')
    prompts = []
    results = []
    decision = socket_events._quick_host_key_decision(
        user_id=user_id,
        socket_sid=sid,
        username='deploy',
        port=22,
        ip_address=None,
        cancelled=lambda: False,
        gateway_attempt=None,
        send_prompt=lambda *args: prompts.append(args),
    )

    thread = threading.Thread(
        target=lambda: results.append(
            decision('target.example', 'ssh-rsa', 'aa:bb', 'target')
        ),
        daemon=True,
    )
    thread.start()
    _wait_for_prompt(prompts)

    socket_events._cancel_ssh_host_key_prompt_for_request(user_id, sid, None)
    thread.join(5)

    assert not thread.is_alive()
    assert results == [False]
    assert socket_events._ssh_host_key_prompts == {}


def test_a_gateway_prompt_ignores_a_foreign_request_id(app, monkeypatch):
    import app.socket_events as socket_events

    user_id, sid = _socket_user(app, 'gateway_prompt_cancel')
    prompts = []
    results = []
    decision = socket_events._quick_host_key_decision(
        user_id=user_id,
        socket_sid=sid,
        username='deploy',
        port=22,
        ip_address=None,
        cancelled=lambda: False,
        gateway_attempt=None,
        send_prompt=lambda *args: prompts.append(args),
        client_request_id='gateway-quick-request',
    )

    thread = threading.Thread(
        target=lambda: results.append(
            decision('bastion.example', 'ssh-rsa', 'aa:bb', 'jump_host')
        ),
        daemon=True,
    )
    thread.start()
    _wait_for_prompt(prompts)

    socket_events._cancel_ssh_host_key_prompt_for_request(
        user_id, sid, 'some-other-request',
    )
    time.sleep(0.05)
    assert results == []
    assert len(socket_events._ssh_host_key_prompts) == 1

    socket_events._cancel_ssh_host_key_prompt_for_request(
        user_id, sid, 'gateway-quick-request',
    )
    thread.join(5)

    assert not thread.is_alive()
    assert results == [False]
    assert socket_events._ssh_host_key_prompts == {}


def test_gateway_attempt_cancellation_stops_the_prompt_poll(app, monkeypatch):
    import app.socket_events as socket_events

    user_id, sid = _socket_user(app, 'gateway_attempt_cancel')

    class _Attempt:
        def __init__(self):
            self._event = threading.Event()

        def is_set(self):
            return self._event.is_set()

        def cancel(self):
            self._event.set()

    attempt = _Attempt()
    prompts = []
    results = []
    decision = socket_events._quick_host_key_decision(
        user_id=user_id,
        socket_sid=sid,
        username='deploy',
        port=22,
        ip_address=None,
        cancelled=lambda: False,
        gateway_attempt=attempt,
        send_prompt=lambda *args: prompts.append(args),
        client_request_id='gateway-quick-request',
    )

    thread = threading.Thread(
        target=lambda: results.append(
            decision('bastion.example', 'ssh-rsa', 'aa:bb', 'jump_host')
        ),
        daemon=True,
    )
    thread.start()
    _wait_for_prompt(prompts)

    attempt.cancel()
    thread.join(5)

    assert not thread.is_alive()
    assert results == [False]
    assert socket_events._ssh_host_key_prompts == {}
