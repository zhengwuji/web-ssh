import json
import re
from pathlib import Path


I18N_SOURCE_PATH = Path('static/js/i18n.js')
I18N_BUNDLE_DIRECTORY = Path('static/js/i18n')
ENGLISH_BLOCK_PATTERN = re.compile(r'^    en: \{$', re.MULTILINE)
ENGLISH_ENTRY_PATTERN = re.compile(
    r"""^        '([^']+)': (?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'),?$""",
    re.MULTILINE,
)

TERMINOLOGY = {
    'en': ('Quick Connect', 'Hosts'),
    'vi': ('Kết nối nhanh', 'Máy chủ'),
    'de': ('Schnellverbindung', 'Hosts'),
    'fr': ('Connexion rapide', 'Hôtes'),
    'es': ('Conexión rápida', 'Hosts'),
    'zh': ('快速连接', '主机'),
}

LEGACY_CONNECTION_TERMS = {
    'en': r'\bprofiles?\b',
    'vi': r'(?:hồ sơ|cấu hình)',
    'de': r'\bprofil(?:e|en|s)?\b',
    'fr': r'\bprofils?\b',
    'es': r'\bperfiles?\b',
    'zh': r'配置(?:文件)?',
}

SAVED_CONNECTION_COPY_KEYS = {
    'connection.profileUnavailable',
    'connection.loadProfile',
    'connection.selectProfile',
    'connection.saveAsProfile',
    'connection.profileName',
    'profiles.create',
    'profiles.none',
    'profiles.saveFailed',
    'profiles.saved',
    'commandSets.manageHint',
    'commandModes.parametersTooltip',
    'commandSets.legacyNotice',
}


def _inline_english_entries():
    """Read the English table that ships inline in static/js/i18n.js.

    Only English stays inline so the workspace first load does not pay for
    every locale; the other bundles are fetched on demand.
    """
    source = I18N_SOURCE_PATH.read_text(encoding='utf-8')
    start = ENGLISH_BLOCK_PATTERN.search(source)
    assert start is not None, 'static/js/i18n.js must keep an inline en table'
    end = source.index('\n};', start.end())
    entries = {}
    for match in ENGLISH_ENTRY_PATTERN.finditer(source[start.end():end]):
        raw = match.group(2) if match.group(2) is not None else match.group(3)
        entries[match.group(1)] = raw.replace("\\'", "'").replace('\\"', '"')
    return entries


def _bundle_locales():
    """Read the lazily fetched static/js/i18n/<lang>.json bundles."""
    locales = {}
    for bundle_path in sorted(I18N_BUNDLE_DIRECTORY.glob('*.json')):
        locales[bundle_path.stem] = json.loads(
            bundle_path.read_text(encoding='utf-8')
        )
    return locales


def _translations_by_locale():
    locales = {'en': _inline_english_entries()}
    locales.update(_bundle_locales())
    return locales


def test_all_locales_have_matching_translation_keys():
    translations = _translations_by_locale()
    keys_by_locale = {
        locale: set(entries) for locale, entries in translations.items()
    }

    assert set(keys_by_locale) == {'en', 'vi', 'de', 'fr', 'es', 'zh'}
    assert all(
        keys == keys_by_locale['en']
        for keys in keys_by_locale.values()
    )
    assert all(
        'connection.tailscaleSSH' in keys
        for keys in keys_by_locale.values()
    )
    assert all(
        {
            'connection.commandSet',
            'connection.commandSetHint',
            'commandSets.manage',
            'commandSets.create',
            'commandSets.saveToLibrary',
            'commandSets.useSudo',
            'commandSets.useSudoHint',
            'commandSets.sudoBadge',
        } <= keys
        for keys in keys_by_locale.values()
    )
    assert all(
        {
            'profiles.search',
            'profiles.searchPlaceholder',
            'profiles.group',
            'profiles.groupPlaceholder',
            'profiles.favorites',
            'profiles.ungrouped',
            'profiles.favorite',
            'profiles.unfavorite',
            'profiles.noMatches',
        } <= keys
        for keys in keys_by_locale.values()
    )
    assert all(
        {
            'palette.actions',
            'palette.hosts',
            'palette.sessions',
            'palette.savedHost',
            'palette.activeSession',
            'palette.searchPlaceholder',
        } <= keys
        for keys in keys_by_locale.values()
    )
    assert all(
        {
            'keys.addNew',
            'keys.add',
            'keys.rename',
            'keys.renameNamed',
            'keys.saveName',
            'keys.renameFailed',
            'connection.connectBusy',
        } <= keys
        for keys in keys_by_locale.values()
    )


def test_saved_connection_and_quick_connect_terms_are_consistent():
    translations = _translations_by_locale()
    quick_keys = {
        'connection.newConnection',
        'connection.newSSHConnection',
        'shortcuts.newConnection',
    }
    saved_keys = {
        'connection.savedProfiles',
        'profiles.manage',
        'fm.qc.savedProfiles',
    }

    for locale, values in translations.items():
        quick_connect, saved_connections = TERMINOLOGY[locale]
        assert {values[key] for key in quick_keys} == {quick_connect}
        assert {values[key] for key in saved_keys} == {saved_connections}
        assert values['panes.newConnection'] == f'+ {quick_connect}'
        assert values['fm.newConnection'] == f'+ {quick_connect}...'
        assert quick_connect in values['connection.clickToStart']
        assert quick_connect in values['panes.selectSession']
        assert quick_connect in values['panes.assignInfo']
        for key in SAVED_CONNECTION_COPY_KEYS:
            assert not re.search(
                LEGACY_CONNECTION_TERMS[locale],
                values[key],
                re.IGNORECASE,
            ), f'{locale}:{key} still uses legacy profile terminology'


def test_new_tab_accessible_name_describes_the_connection_launcher():
    source = Path('templates/index.html').read_text(encoding='utf-8')
    new_tab = re.search(r'<button[^>]+id="newTabBtn"[^>]*>', source)

    assert new_tab is not None
    assert 'title="Select a session or use Quick Connect"' in new_tab.group(0)
    assert 'aria-label="Select a session or use Quick Connect"' in new_tab.group(0)
    assert 'data-i18n-title="panes.selectSession"' in new_tab.group(0)
    assert 'data-i18n-aria-label="panes.selectSession"' in new_tab.group(0)


def test_english_visible_fallbacks_avoid_legacy_connection_terms():
    sources = '\n'.join(
        Path(path).read_text(encoding='utf-8')
        for path in (
            'templates/index.html',
            'static/js/app.js',
            'static/js/profile-manager.js',
            'static/js/sftp-file-manager.js',
        )
    )
    for legacy_text in (
        'Load Profile',
        'Select Profile',
        'Profile Name',
        'Create profile',
        'No profiles saved',
        'Failed to save profile',
        'Profile saved successfully',
        'Profile deleted successfully',
        'delete this profile',
        '+ New Connection...',
        'Saved Profiles',
        'This profile still uses',
        'connection profile',
    ):
        assert legacy_text not in sources


def test_all_locales_preserve_translation_placeholders():
    translations = _translations_by_locale()
    placeholders_by_locale = {
        locale: {
            key: set(re.findall(r'\{[a-zA-Z][a-zA-Z0-9_]*\}', value))
            for key, value in entries.items()
        }
        for locale, entries in translations.items()
    }

    english = placeholders_by_locale['en']
    assert all(
        placeholders == english
        for placeholders in placeholders_by_locale.values()
    )


def test_english_command_set_copy_explains_execution_boundaries():
    hint = _inline_english_entries()['connection.commandSetHint'].lower()

    assert 'remote host' in hint
    assert 'not in webssh' in hint
    assert 'tmux' in hint
    assert 'not run again' in hint


def test_all_popup_translation_references_exist_in_every_locale():
    source_paths = (
        sorted(Path('templates').glob('*.html'))
        + sorted(Path('static/js').glob('*.js'))
    )
    referenced_keys = set()
    for source_path in source_paths:
        source = source_path.read_text(encoding='utf-8')
        if source_path.name == 'terminal_appearance.html':
            from jinja2 import Template

            source = Template(source).render()
        referenced_keys.update(
            re.findall(
                r'data-i18n(?:-placeholder|-title|-label|-aria-label|-alt)?="([^"]+)"',
                source,
            )
        )
        referenced_keys.update(
            re.findall(
                r"(?:i18n\.t|window\.i18n\.t|this\.t|(?<![\w.])t)"
                r"\(\s*'([a-z][a-zA-Z0-9_.-]+)'",
                source,
            )
        )

    missing_by_locale = {}
    for locale, locale_keys in _translations_by_locale().items():
        missing = sorted(referenced_keys - set(locale_keys))
        if missing:
            missing_by_locale[locale] = missing

    assert missing_by_locale == {}


def test_recent_settings_and_github_surfaces_are_runtime_localized():
    admin_template = Path('templates/admin.html').read_text(encoding='utf-8')
    security_template = Path('templates/security.html').read_text(encoding='utf-8')
    admin_source = Path('static/js/admin.js').read_text(encoding='utf-8')
    settings_source = Path('static/js/settings-center.js').read_text(encoding='utf-8')
    file_manager_source = Path('static/js/sftp-file-manager.js').read_text(
        encoding='utf-8'
    )

    for key in (
        'admin.filterUsers',
        'admin.githubAuthentication',
        'admin.githubSetupFinish',
        'admin.githubSave',
        'settings.center',
        'settings.securityOverview',
        'settings.professionalThemes',
        'security.passkeysAndMfa',
        'security.githubManagedHint',
        'security.manageGithubHint',
        'security.manageOidcHint',
    ):
        assert re.search(
            rf'data-i18n(?:-placeholder|-title|-label|-aria-label|-alt)?="{re.escape(key)}"',
            admin_template + security_template,
        )

    assert "t('admin.filteredUserCount'" in admin_source
    assert "'admin.githubSecretStored'" in admin_source
    assert "'admin.githubClearSecretConfirm'" in admin_source
    assert "t('settings.languageUpdated'" in settings_source
    assert "t('settings.savingTheme'" in settings_source
    assert "window.addEventListener('languageChanged', renderMobileSelect)" in settings_source
    assert "window.addEventListener('languageChanged', renderGitHubIdentity)" in Path(
        'static/js/webauthn.js'
    ).read_text(encoding='utf-8')
    assert "window.addEventListener('languageChanged'" in file_manager_source
    assert 'data-i18n-aria-label="fm.workspace.leftSources"' in file_manager_source


def test_popup_inputs_use_explicit_placeholder_translation_attribute():
    source = Path('templates/index.html').read_text(encoding='utf-8')
    popup_source = source[source.index('<div class="modal'):source.index(
        '<script src=',
    )]
    translated_fields = re.findall(
        r'<(?:input|textarea)\b[^>]*\bdata-i18n="[^"]+"[^>]*>',
        popup_source,
    )

    assert translated_fields == []


def test_dynamic_popup_select_placeholders_refresh_with_language():
    profile_source = Path('static/js/profile-manager.js').read_text(encoding='utf-8')
    jump_host_source = Path('static/js/jump-host-manager.js').read_text(encoding='utf-8')

    assert re.search(
        r"this\.t\(\s*'connection\.selectProfile'",
        profile_source,
    )
    assert re.search(
        r"this\.t\(\s*'connection\.selectSSHKey'",
        profile_source,
    )
    assert "window.addEventListener('languageChanged'" in jump_host_source
    assert 'window.JumpHostManager.renderSelect();' in jump_host_source


def test_connection_state_messages_use_the_active_locale():
    source = Path('static/js/app.js').read_text(encoding='utf-8')

    for key in (
        'connection.reconnected',
        'connection.lostReconnecting',
        'connection.lostReconnectingAttempt',
        'connection.disconnectedFromServer',
        'connection.reloadRequired',
        'connection.reloadPage',
    ):
        assert f"i18n.t('{key}')" in source


def test_webssh2_pages_use_explicit_placeholder_and_accessible_text_translations():
    source = '\n'.join(
        Path(path).read_text(encoding='utf-8')
        for path in (
            'templates/login.html',
            'templates/register.html',
            'templates/change_password.html',
            'templates/security.html',
        )
    )

    assert not re.search(
        r'<input\b[^>]*\bdata-i18n="[^"]+"[^>]*>',
        source,
    )
    assert 'data-i18n-alt="security.totpQrCode"' in source


def test_admin_authentication_feature_controls_are_fully_translatable():
    template = Path('templates/admin.html').read_text(encoding='utf-8')
    script = '\n'.join(
        Path(path).read_text(encoding='utf-8')
        for path in ('static/js/admin.js', 'static/js/security-ui.js')
    )

    for key in (
        'admin.ldapDirectory',
        'admin.ldapCheckHint',
        'admin.checkConnection',
        'admin.notChecked',
        'admin.authenticationFeatures',
        'admin.authenticationFeaturesHint',
        'admin.featureStatusNotLoaded',
        'admin.directoryUsername',
        'admin.newLocalPasswordAfterUnlinking',
        'admin.unlinkRestoresLocalAuth',
    ):
        assert f'data-i18n="{key}"' in template

    for key in (
        'admin.featureActive',
        'admin.deploymentConfiguration',
        'admin.openSetupGuide',
        'admin.featureStatusLoaded',
        'admin.noAuthenticationFeatures',
        'admin.featureStatusLoading',
    ):
        assert f"'{key}'" in script


def test_workspace_native_controls_are_fully_translatable():
    source = Path('templates/index.html').read_text(encoding='utf-8')

    for key in (
        'workspace.closeBroadcast',
        'workspace.dropFile',
        'workspace.dropDestination',
        'terminal.searchPlaceholder',
        'terminal.searchPrevious',
        'terminal.searchNext',
        'terminal.closeSearch',
        'workspace.activeSessionFiles',
        'sessionCommands.panelLabel',
    ):
        assert key in source


def test_auth_validation_hints_match_the_shared_controller_contract():
    register = Path('templates/register.html').read_text(encoding='utf-8')
    change = Path('templates/change_password.html').read_text(encoding='utf-8')

    for field_id in (
        'registerUsernameHint',
        'registerPasswordHint',
        'registerConfirmHint',
    ):
        assert f'id="{field_id}"' in register
    for field_id in (
        'currentPasswordHint',
        'newPasswordHint',
        'confirmPasswordHint',
    ):
        assert f'id="{field_id}"' in change

    assert 'function toggleLangDropdown()' not in register
    assert 'function toggleLangDropdown()' not in Path(
        'templates/login.html'
    ).read_text(encoding='utf-8')
