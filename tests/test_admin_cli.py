import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _maintenance_cli(
    data_dir,
    *arguments,
    environment_overrides=None,
    app_target='start',
    flask_module='flask',
):
    environment = os.environ.copy()
    environment.update({
        'DATA_DIR': str(data_dir),
        'DEBUG': 'True',
        'SECRET_KEY': 'maintenance-cli-test-secret',
    })
    if environment_overrides:
        environment.update(environment_overrides)
    return subprocess.run(
        [
            sys.executable,
            '-m',
            flask_module,
            '--app',
            app_target,
            *arguments,
        ],
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )


def _missing_ldap_runtime_environment(tmp_path):
    return {
        'LDAP_ENABLED': 'true',
        'LDAP_URL': 'ldaps://directory.example.com:636',
        'LDAP_BASE_DN': 'dc=example,dc=com',
        'LDAP_BIND_DN': 'cn=service,dc=example,dc=com',
        'LDAP_BIND_PASSWORD_FILE': str(tmp_path / 'missing-ldap-password'),
        'LDAP_CA_FILE': str(tmp_path / 'missing-ldap-ca.pem'),
        'LDAP_USER_FILTER': '(&(objectClass=person)(uid={username}))',
        'LDAP_UNIQUE_ID_ATTRIBUTE': 'entryUUID',
    }


def test_maintenance_help_uses_safe_factory_without_runtime_or_storage(tmp_path):
    data_dir = tmp_path / 'connection-store'

    result = _maintenance_cli(
        data_dir,
        'connection-store',
        '--help',
        app_target='app:create_app',
        environment_overrides=_missing_ldap_runtime_environment(tmp_path),
    )

    assert result.returncode == 0, result.stderr
    assert 'Usage:' in result.stdout
    assert not data_dir.exists()


def test_maintenance_detection_supports_all_commands_and_flask_entrypoints():
    import app as app_module

    entrypoints = (
        ('flask', None),
        ('python', 'flask.__main__'),
        ('python', 'flask.cli'),
    )
    for command in app_module._MAINTENANCE_COMMANDS:
        for program_name, main_module_name in entrypoints:
            assert app_module._is_maintenance_cli_invocation(
                arguments=['--app', 'app:create_app', command, '--help'],
                program_name=program_name,
                main_module_name=main_module_name,
            ) is True


def test_factory_target_connection_store_initializes_inside_command(tmp_path):
    data_dir = tmp_path / 'connection-store-operation'

    result = _maintenance_cli(
        data_dir,
        'connection-store',
        'list',
        '--username',
        'missing-user',
        '--kind',
        'profiles',
        '--confirm-offline',
        app_target='app:create_app',
        environment_overrides=_missing_ldap_runtime_environment(tmp_path),
    )

    assert result.returncode != 0
    assert 'Account not found' in result.stderr
    assert 'LDAP secret file is unavailable' not in result.stderr
    assert (data_dir / 'app.db').is_file()


def test_factory_target_connection_store_locks_before_initialization(
    tmp_path,
    monkeypatch,
):
    import config
    from app.backup_coordination import operation_lock

    data_dir = tmp_path / 'locked-connection-store-operation'
    operation_dir = tmp_path / 'operations'
    monkeypatch.setattr(config, 'DATA_DIR', data_dir)
    monkeypatch.setattr(config, 'BACKUP_TEMP_DIR', operation_dir)
    monkeypatch.setattr(config, 'BACKUP_OPERATION_TIMEOUT', 1)

    with operation_lock():
        result = _maintenance_cli(
            data_dir,
            'connection-store',
            'list',
            '--username',
            'missing-user',
            '--kind',
            'profiles',
            '--confirm-offline',
            app_target='app:create_app',
            environment_overrides={
                **_missing_ldap_runtime_environment(tmp_path),
                'BACKUP_TEMP_DIR': str(operation_dir),
                'BACKUP_OPERATION_TIMEOUT': '1',
            },
        )

    assert result.returncode != 0
    assert 'another backup or restore operation is active' in result.stderr
    assert not data_dir.exists()


def test_factor_bootstrap_missing_user_skips_ldap_runtime_files(tmp_path):
    result = _maintenance_cli(
        tmp_path / 'factor-bootstrap-ldap-data',
        'issue-factor-bootstrap',
        '--username',
        'missing-user',
        '--action',
        'passkey.enroll',
        environment_overrides=_missing_ldap_runtime_environment(tmp_path),
    )

    assert result.returncode != 0
    assert 'Eligible account not found' in result.stderr
    assert 'LDAP secret file is unavailable' not in result.stderr


def test_normal_app_factory_still_requires_ldap_runtime_files(tmp_path):
    environment = os.environ.copy()
    environment.update({
        'DATA_DIR': str(tmp_path / 'normal-start-data'),
        'DEBUG': 'True',
        'SECRET_KEY': 'normal-start-test-secret',
        **_missing_ldap_runtime_environment(tmp_path),
    })

    result = subprocess.run(
        [
            sys.executable,
            '-c',
            (
                'from app import create_app; '
                'create_app(initialize_storage=False, start_runtime=False, '
                'initialize_oidc=False)'
            ),
        ],
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )

    assert result.returncode != 0
    assert 'LDAP secret file is unavailable' in result.stderr


def test_factory_target_nonmaintenance_command_keeps_ldap_fail_fast(tmp_path):
    data_dir = tmp_path / 'nonmaintenance-data'

    result = _maintenance_cli(
        data_dir,
        'routes',
        app_target='app:create_app',
        environment_overrides=_missing_ldap_runtime_environment(tmp_path),
    )

    assert result.returncode != 0
    assert 'LDAP secret file is unavailable' in result.stderr
    assert not data_dir.exists()


def test_skipped_ldap_runtime_validation_is_not_marked_ready(
    monkeypatch,
    tmp_path,
):
    import app as app_module
    import config

    # A complete LDAP configuration passes the fail-closed config validation;
    # only the runtime files are missing, which is what a maintenance command
    # deliberately skips.
    for key, value in _missing_ldap_runtime_environment(tmp_path).items():
        monkeypatch.setenv(key, value)
    monkeypatch.setattr(config, 'LDAP_ENABLED', True)
    for key, value in _missing_ldap_runtime_environment(tmp_path).items():
        monkeypatch.setattr(config, key, value)
    monkeypatch.setattr(
        app_module,
        '_is_maintenance_cli_invocation',
        lambda: True,
    )

    maintenance_app = app_module.create_app()

    assert maintenance_app.extensions['maintenance_cli_invocation'] is True
    assert maintenance_app.extensions['security_feature_readiness']['ldap'] == (
        False,
        'LDAP runtime validation did not complete.',
    )


def _admin(app, username):
    from app.models import User

    with app.app_context():
        return User.query.filter_by(username=username).first()


def test_create_admin_maintenance_cli_initializes_storage_and_exits(tmp_path):
    data_dir = tmp_path / 'new-data'
    password_file = tmp_path / 'admin-password'
    password_file.write_text('standalone-admin-password\n', encoding='utf-8')
    environment = os.environ.copy()
    environment.update({
        'DATA_DIR': str(data_dir),
        'DEBUG': 'True',
        'SECRET_KEY': 'maintenance-cli-test-secret',
    })

    result = subprocess.run(
        [
            sys.executable,
            '-m',
            'flask',
            '--app',
            'start',
            'create-admin',
            '--username',
            'standaloneadmin',
            '--password-file',
            str(password_file),
        ],
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    assert (data_dir / 'app.db').is_file()


def test_create_admin_interactively_hides_password(app):
    password = 'strong-admin-password'
    runner = app.test_cli_runner()

    result = runner.invoke(
        args=['create-admin', '--username', 'adminuser'],
        input=f'{password}\n{password}\n',
    )

    assert result.exit_code == 0
    assert password not in result.output
    user = _admin(app, 'adminuser')
    assert user is not None
    assert user.is_admin is True
    assert user.check_password(password)


@pytest.mark.parametrize(
    ('password', 'expected_error'),
    (
        pytest.param('short', 'at least 8 characters', id='weak'),
        pytest.param('a' * 73, '72 bytes', id='overlong'),
    ),
)
def test_create_admin_rejects_invalid_interactive_passwords(
    app,
    password,
    expected_error,
):
    runner = app.test_cli_runner()

    result = runner.invoke(
        args=['create-admin', '--username', 'invalidadmin'],
        input=f'{password}\n{password}\n',
    )

    assert result.exit_code != 0
    assert password not in result.output
    assert expected_error in result.output
    assert _admin(app, 'invalidadmin') is None


def test_create_admin_promotes_existing_user_without_resetting_password(app):
    from app.auth import register_user

    password = 'existing-user-password'
    with app.app_context():
        user, error = register_user('existinguser', password)
        assert error is None
        original_hash = user.password_hash

    result = app.test_cli_runner().invoke(
        args=['create-admin', '--username', 'existinguser'],
    )

    assert result.exit_code == 0
    user = _admin(app, 'existinguser')
    assert user.is_admin is True
    assert user.password_hash == original_hash
    assert user.check_password(password)


def test_create_admin_rejects_password_file_for_existing_user(
    app,
    tmp_path,
):
    from app.auth import register_user

    with app.app_context():
        bootstrap, bootstrap_error = register_user(
            'bootstrapadmin',
            'bootstrap-password',
        )
        assert bootstrap_error is None
        assert bootstrap.is_admin is True
        user, error = register_user(
            'existingfileuser',
            'existing-user-password',
        )
        assert error is None
        original_hash = user.password_hash
    password_file = tmp_path / 'replacement-password'
    password_file.write_text('replacement-password\n', encoding='utf-8')

    result = app.test_cli_runner().invoke(
        args=[
            'create-admin',
            '--username',
            'existingfileuser',
            '--password-file',
            str(password_file),
        ],
    )

    assert result.exit_code != 0
    user = _admin(app, 'existingfileuser')
    assert user.is_admin is False
    assert user.password_hash == original_hash


def test_create_admin_rejects_promoting_ldap_managed_user(app):
    from app.auth import register_user
    from app.models import LDAPIdentity, db

    with app.app_context():
        admin, admin_error = register_user(
            'localadmin',
            'local-admin-password',
        )
        assert admin_error is None
        assert admin.is_admin is True
        user, error = register_user(
            'directoryuser',
            'existing-user-password',
        )
        assert error is None
        db.session.add(LDAPIdentity(
            user_id=user.id,
            provider='default',
            subject='stable-directory-user-id',
            directory_username='directoryuser',
            distinguished_name='uid=directoryuser,dc=example,dc=com',
        ))
        db.session.commit()

    result = app.test_cli_runner().invoke(
        args=['create-admin', '--username', 'directoryuser'],
    )

    assert result.exit_code != 0
    assert 'LDAP-managed accounts cannot be administrators' in result.output
    user = _admin(app, 'directoryuser')
    assert user.is_admin is False


def test_create_admin_rejects_promoting_github_managed_user(app):
    from app.auth import register_user
    from app.models import GitHubIdentity, db

    with app.app_context():
        admin, admin_error = register_user(
            'githubbreakglass',
            'local-admin-password',
        )
        assert admin_error is None
        assert admin.is_admin is True
        user, error = register_user(
            'githubmanageduser',
            'existing-user-password',
        )
        assert error is None
        db.session.add(GitHubIdentity(
            user_id=user.id,
            github_user_id='424242',
            login='github-managed-user',
            provisioned_by_github=True,
        ))
        db.session.commit()

    result = app.test_cli_runner().invoke(
        args=['create-admin', '--username', 'githubmanageduser'],
    )

    assert result.exit_code != 0
    assert 'GitHub-managed accounts cannot be administrators' in result.output
    user = _admin(app, 'githubmanageduser')
    assert user.is_admin is False


def test_create_admin_reads_password_file_and_strips_one_newline(
    app,
    tmp_path,
):
    password = 'file-admin-password'
    password_file = tmp_path / 'admin-password'
    password_file.write_text(f'{password}\n', encoding='utf-8')

    result = app.test_cli_runner().invoke(
        args=[
            'create-admin',
            '--username',
            'fileadmin',
            '--password-file',
            str(password_file),
        ],
    )

    assert result.exit_code == 0
    assert password not in result.output
    user = _admin(app, 'fileadmin')
    assert user is not None
    assert user.is_admin is True
    assert user.check_password(password)


def test_create_admin_rejects_password_file_symlink(app, tmp_path):
    target = tmp_path / 'password-target'
    target.write_text('strong-admin-password\n', encoding='utf-8')
    link = tmp_path / 'password-link'
    try:
        link.symlink_to(target)
    except OSError as exc:
        pytest.skip(f'symlinks unavailable: {exc}')

    result = app.test_cli_runner().invoke(
        args=[
            'create-admin',
            '--username',
            'linkadmin',
            '--password-file',
            str(link),
        ],
    )

    assert result.exit_code != 0
    assert 'symbolic link' in result.output.lower()
    assert _admin(app, 'linkadmin') is None


def test_create_admin_rejects_password_file_directory(app, tmp_path):
    result = app.test_cli_runner().invoke(
        args=[
            'create-admin',
            '--username',
            'directoryadmin',
            '--password-file',
            str(tmp_path),
        ],
    )

    assert result.exit_code != 0
    assert 'regular file' in result.output.lower()
    assert _admin(app, 'directoryadmin') is None


def test_create_admin_audits_success_without_password_material(app, caplog):
    password = 'audit-admin-password'

    result = app.test_cli_runner().invoke(
        args=['create-admin', '--username', 'auditadmin'],
        input=f'{password}\n{password}\n',
    )

    assert result.exit_code == 0
    records = [
        record
        for record in caplog.records
        if record.name == 'security_audit'
    ]
    assert any(
        record.getMessage() == 'ADMIN_BOOTSTRAP_SUCCESS'
        and record.extra_data == {
            'user': 'auditadmin',
            'action': 'created',
        }
        for record in records
    )
    assert password not in repr(records)


def test_warn_if_no_admin_reports_missing_bootstrap(caplog, app):
    from app.cli import warn_if_no_admin

    caplog.clear()
    with app.app_context():
        warn_if_no_admin()

    assert any(
        'No administrator account exists' in record.getMessage()
        for record in caplog.records
    )


def test_fresh_production_defaults_to_closed_registration():
    env = os.environ.copy()
    env['SECRET_KEY'] = 'admin-cli-config-test'
    env['DEBUG'] = 'False'
    env['CORS_ORIGINS'] = 'http://localhost:5000'
    env['PYTHONIOENCODING'] = 'utf-8'
    env.pop('REGISTRATION_ENABLED', None)

    result = subprocess.run(
        [
            sys.executable,
            '-c',
            (
                'import config; '
                'raise SystemExit(0 if not config.REGISTRATION_ENABLED else 1)'
            ),
        ],
        cwd=os.getcwd(),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_saved_registration_setting_is_not_overwritten(
    app,
    tmp_path,
    monkeypatch,
):
    from app import app_settings
    from app.storage_migrations import CURRENT_STORAGE_VERSIONS

    path = tmp_path / 'app_settings.json'
    original = json.dumps({
        'schema_version': CURRENT_STORAGE_VERSIONS['app_settings'],
        'registration_enabled': True,
    }).encode('utf-8')
    path.write_bytes(original)
    monkeypatch.setattr(app_settings, '_SETTINGS_FILE', path)
    monkeypatch.setattr(
        app_settings.config,
        'REGISTRATION_ENABLED',
        False,
    )

    assert app_settings.is_registration_enabled() is True
    assert path.read_bytes() == original


def _create_user(app, username, password, *, is_admin=False):
    from app.models import User, db

    with app.app_context():
        user = User(username=username, is_admin=is_admin)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return user.id


def _user(app, username):
    from app.models import User

    with app.app_context():
        return User.query.filter_by(username=username).first()


def test_reset_password_rotates_the_hash_and_the_auth_generation(app):
    user_id = _create_user(app, 'resetuser', 'original-password')
    before = _user(app, 'resetuser')
    original_hash = before.password_hash
    original_generation = before.auth_generation

    result = app.test_cli_runner().invoke(
        args=['reset-password', '--username', 'resetuser'],
        input='replacement-password\nreplacement-password\n',
    )

    assert result.exit_code == 0, result.output
    assert 'replacement-password' not in result.output

    after = _user(app, 'resetuser')
    assert after.id == user_id
    assert after.password_hash != original_hash
    assert after.check_password('replacement-password')
    assert not after.check_password('original-password')
    # Every browser session derived from the old credentials must be invalid.
    assert after.auth_generation == int(original_generation or 0) + 1


def test_reset_password_accepts_a_password_file(app, tmp_path):
    _create_user(app, 'resetfileuser', 'original-password')
    password_file = tmp_path / 'new-password'
    password_file.write_text('file-replacement\n', encoding='utf-8')

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetfileuser',
            '--password-file',
            str(password_file),
        ],
    )

    assert result.exit_code == 0, result.output
    assert _user(app, 'resetfileuser').check_password('file-replacement')


def test_reset_password_reads_stdin_without_echoing_it(app):
    _create_user(app, 'resetstdinuser', 'original-password')

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetstdinuser',
            '--password-stdin',
        ],
        input='stdin-replacement\n',
    )

    assert result.exit_code == 0, result.output
    assert 'stdin-replacement' not in result.output
    assert _user(app, 'resetstdinuser').check_password('stdin-replacement')


def test_reset_password_generate_prints_the_new_password_once(app):
    _create_user(app, 'resetgenuser', 'original-password')

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetgenuser',
            '--generate',
        ],
    )

    assert result.exit_code == 0, result.output
    assert 'New password:' in result.output

    printed = result.output.split('New password:', 1)[1].strip().splitlines()[0]
    assert len(printed) >= 8
    assert _user(app, 'resetgenuser').check_password(printed)


@pytest.mark.parametrize(
    'password, message',
    [
        ('short', 'at least 8 characters'),
        ('a' * 73, '72 bytes'),
    ],
)
def test_reset_password_rejects_invalid_passwords(app, password, message):
    _create_user(app, 'resetinvaliduser', 'original-password')
    original_hash = _user(app, 'resetinvaliduser').password_hash

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetinvaliduser',
            '--password-stdin',
        ],
        input=f'{password}\n',
    )

    assert result.exit_code != 0
    assert message in result.output
    assert _user(app, 'resetinvaliduser').password_hash == original_hash


def test_reset_password_rejects_unknown_and_managed_accounts(app):
    missing = app.test_cli_runner().invoke(
        args=['reset-password', '--username', 'ghostuser', '--generate'],
    )
    assert missing.exit_code != 0
    assert 'Account not found' in missing.output

    _create_user(app, 'resetldapuser', 'original-password')
    with app.app_context():
        from app.models import LDAPIdentity, User, db

        user = User.query.filter_by(username='resetldapuser').first()
        db.session.add(LDAPIdentity(
            user_id=user.id,
            provider='ldap',
            subject='ldap-stable-subject',
            directory_username='resetldapuser',
            distinguished_name='uid=resetldapuser,dc=example,dc=com',
        ))
        db.session.commit()

    managed = app.test_cli_runner().invoke(
        args=['reset-password', '--username', 'resetldapuser', '--generate'],
    )
    assert managed.exit_code != 0
    assert 'directory' in managed.output.lower()


def test_reset_password_rejects_conflicting_password_sources(app, tmp_path):
    _create_user(app, 'resetconflictuser', 'original-password')
    password_file = tmp_path / 'conflict-password'
    password_file.write_text('conflict-replacement\n', encoding='utf-8')

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetconflictuser',
            '--generate',
            '--password-file',
            str(password_file),
        ],
    )

    assert result.exit_code != 0
    assert 'only one of' in result.output.lower()
    assert _user(app, 'resetconflictuser').check_password('original-password')


def test_reset_password_audit_omits_password_material(app, caplog):
    _create_user(app, 'resetaudituser', 'original-password')

    result = app.test_cli_runner().invoke(
        args=[
            'reset-password',
            '--username',
            'resetaudituser',
            '--password-stdin',
        ],
        input='audited-replacement\n',
    )

    assert result.exit_code == 0, result.output
    records = [
        record
        for record in caplog.records
        if record.name == 'security_audit'
    ]
    assert any(
        record.getMessage() == 'PASSWORD_RESET_SUCCESS'
        and record.extra_data == {
            'user': 'resetaudituser',
            'method': 'password-stdin',
        }
        for record in records
    )
    assert 'audited-replacement' not in repr(records)


def test_reset_password_runs_through_the_cli_entrypoint(tmp_path):
    data_dir = tmp_path / 'reset-password-data'

    password_file = tmp_path / 'admin-password'
    password_file.write_text('service-admin-password\n', encoding='utf-8')
    admin = _maintenance_cli(
        data_dir,
        'create-admin',
        '--username',
        'resetserviceadmin',
        '--password-file',
        str(password_file),
    )
    assert admin.returncode == 0, admin.stderr

    replacement = tmp_path / 'replacement-password'
    replacement.write_text('service-replacement\n', encoding='utf-8')
    result = _maintenance_cli(
        data_dir,
        'reset-password',
        '--username',
        'resetserviceadmin',
        '--password-file',
        str(replacement),
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert 'Password reset for: resetserviceadmin' in result.stdout


def test_legacy_role_migration_promotes_only_oldest_existing_user(app):
    from sqlalchemy import text
    from app.models import db, ensure_user_columns

    with app.app_context():
        db.session.execute(text('DROP TABLE users'))
        db.session.execute(text(
            'CREATE TABLE users ('
            'id INTEGER PRIMARY KEY, '
            'username VARCHAR(80) NOT NULL UNIQUE, '
            'password_hash VARCHAR(128) NOT NULL, '
            'created_at DATETIME, '
            'last_login DATETIME'
            ')'
        ))
        db.session.execute(text(
            "INSERT INTO users (id, username, password_hash) VALUES "
            "(2, 'newer', 'unused'), "
            "(1, 'oldest', 'unused')"
        ))
        db.session.commit()

        ensure_user_columns()
        rows = db.session.execute(text(
            'SELECT id, is_admin, is_locked, auth_generation '
            'FROM users ORDER BY id'
        )).all()

        assert rows == [(1, 1, 0, 0), (2, 0, 0, 0)]

        ensure_user_columns()
        repeated = db.session.execute(text(
            'SELECT id, is_admin, is_locked, auth_generation '
            'FROM users ORDER BY id'
        )).all()
        assert repeated == rows
