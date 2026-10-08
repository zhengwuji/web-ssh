/*
 * Header workspace chrome: theme selector, language selector, account
 * dropdown, and the wired-up global navigation buttons.
 *
 * Replaces the former inline <script> block at the end of index.html so the
 * page can run under a strict CSP (script-src 'self') — including the
 * inline onclick handlers that used to live on the buttons themselves.
 */
(function() {
    'use strict';

    function initThemeSelectorHeader() {
        const currentTheme = document.body.getAttribute('data-theme') || 'glass';
        window.ThemePreference?.store(currentTheme);
        const select = document.getElementById('settingsThemeSelect');

        if (select) {
            select.value = currentTheme;
            select.addEventListener('change', () => {
                applyTheme(select.value);
            });
        }
    }

    function applyTheme(themeId) {
        if (!window.ThemePreference?.isValid(themeId)) {
            return;
        }
        document.body.setAttribute('data-theme', themeId);
        window.ThemePreference.store(themeId);
        if (window.socket) {
            window.socket.emit('set_theme', { theme: themeId });
        }
        const select = document.getElementById('settingsThemeSelect');
        if (select) select.value = themeId;
        if (window.TerminalManager && typeof TerminalManager.applyThemeToAll === 'function') {
            TerminalManager.applyThemeToAll();
        }
    }

    function initLanguageSelectorHeader() {
        const select = document.getElementById('settingsLanguageSelect');
        if (!select || !window.i18n) return;
        const languages = i18n.getLanguages();
        const currentLang = i18n.getLanguage();

        select.replaceChildren();
        languages.forEach(lang => {
            const option = document.createElement('option');
            option.value = lang.code;
            option.textContent = `${lang.flag} ${lang.name}`;
            select.appendChild(option);
        });
        select.value = currentLang;
        select.addEventListener('change', () => {
            i18n.setLanguage(select.value);
        });
    }

    function closeAccountDropdownHeader() {
        document.getElementById('accountDropdownHeader')?.classList.remove('show');
        document.getElementById('accountBtnHeader')?.setAttribute('aria-expanded', 'false');
    }

    function toggleAccountDropdownHeader(event) {
        if (event) {
            event.stopPropagation();
        }
        const dropdown = document.getElementById('accountDropdownHeader');
        if (!dropdown) {
            return;
        }
        if (dropdown.classList.contains('show')) {
            closeAccountDropdownHeader();
            return;
        }
        dropdown.classList.add('show');
        document.getElementById('accountBtnHeader')?.setAttribute('aria-expanded', 'true');
    }

    function wireFormerInlineHandlers() {
        document.getElementById('fileTransferBtn')?.addEventListener('click', () => {
            window.openFileManager?.();
        });

        const more = (action) => (event) => {
            event.preventDefault();
            window.primaryWorkspaceController?.showWorkspaces();
            action();
            window.mobileAppShell?.closeMoreMenu();
        };

        document.getElementById('mobileQuickConnectAction')?.addEventListener('click', (event) => {
            event.preventDefault();
            window.openDefaultConnectionModal?.();
            window.mobileAppShell?.closeMoreMenu();
        });
        document.getElementById('mobileToolsAction')?.addEventListener('click', more(() => {
            window.workspaceLayoutController?.setNotesOpen(true, 'user');
        }));
        document.getElementById('mobileBroadcastAction')?.addEventListener('click', more(() => {
            window.BroadcastInput?.toggle();
        }));
        document.getElementById('mobileTranscriptAction')?.addEventListener('click', more(() => {
            document.getElementById('saveTranscriptBtn')?.click();
        }));

        document.getElementById('accountBtnHeader')?.addEventListener('click', (event) => {
            toggleAccountDropdownHeader(event);
        });
    }

    document.getElementById('accountDropdownHeader')?.addEventListener('click', (e) => {
        if (e.target.closest('.account-action')) {
            closeAccountDropdownHeader();
        }
    });

    window.addEventListener('click', (e) => {
        if (!e.target.closest('.account-selector')) {
            closeAccountDropdownHeader();
        }
    });

    document.addEventListener('DOMContentLoaded', () => {
        initThemeSelectorHeader();
        initLanguageSelectorHeader();
        wireFormerInlineHandlers();
        window.webssh2Shell = window.WebSSH2Shell?.init({
            sessionManager: SessionManager,
            document,
        });
        window.accountWorkspacePulse = window.AccountWorkspacePulseModule?.createAccountWorkspacePulse({
            sessionManager: SessionManager,
            document,
            window,
            translate: key => window.i18n ? i18n.t(key) : key,
        });
        window.accountWorkspacePulse?.init();
    });

    window.applyTheme = applyTheme;
    window.toggleAccountDropdownHeader = toggleAccountDropdownHeader;
    window.closeAccountDropdownHeader = closeAccountDropdownHeader;
    window.initThemeSelectorHeader = initThemeSelectorHeader;
    window.initLanguageSelectorHeader = initLanguageSelectorHeader;
})();
