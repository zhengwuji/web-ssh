const globals = require('globals');

// Cross-file globals of the no-build frontend: classic scripts attach these
// to window and later files read them, so they must be declared explicitly.
const appGlobals = {
    APP_ROOT: 'readonly',
    i18n: 'readonly',
    socket: 'readonly',
    ModalManager: 'readonly',
    SessionManager: 'readonly',
    TerminalManager: 'readonly',
    ThemePreference: 'readonly',
    showNotification: 'readonly',
    openFileManager: 'readonly',
    openDefaultConnectionModal: 'readonly',
    primaryWorkspaceController: 'readonly',
    workspaceLayoutController: 'readonly',
    mobileAppShell: 'readonly',
    BroadcastInput: 'readonly',
    getSFTPFileManager: 'readonly',
    WebSSHSocketProtocol: 'readonly',
    applyTheme: 'readonly',
    toggleAccountDropdownHeader: 'readonly',
    closeAccountDropdownHeader: 'readonly',
    initThemeSelectorHeader: 'readonly',
    initLanguageSelectorHeader: 'readonly',
    webssh2Shell: 'readonly',
    accountWorkspacePulse: 'readonly',
    WEBSSH_TRANSFER_LIMITS: 'readonly',
    WEBSSH_SSH_INPUT_LIMITS: 'readonly',
    WEBSSH_TARGET_OS_BY_SESSION: 'writeable',
    // UMD guards reference CommonJS locals under `typeof` first; declaring
    // them keeps the browser lint context happy for node-testable modules.
    module: 'writeable',
    require: 'readonly',
    // Vendored browser globals and cross-file classes.
    io: 'readonly',
    hljs: 'readonly',
    Terminal: 'readonly',
    FitAddon: 'readonly',
    SearchAddon: 'readonly',
    ProfileManager: 'readonly',
    ProfileLauncherUtils: 'readonly',
    CommandLibrary: 'readonly',
    BinaryTransferClient: 'readonly',
    FileTransferManager: 'readonly',
    ConnectionLauncher: 'readonly',
    ConnectionCommandManager: 'readonly',
    CommandWorkspace: 'readonly',
    CommandPaletteUtils: 'readonly',
    CommandSetManager: 'readonly',
};

module.exports = [
  {
    files: ['static/js/**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'script',
      globals: {
        ...globals.browser,
        ...appGlobals,
      },
    },
    rules: {
      'no-unused-vars': ['error', {
        args: 'after-used',
        caughtErrors: 'all',
      }],
      'no-undef': 'error',
      'eqeqeq': ['error', 'smart'],
    },
  },
];
