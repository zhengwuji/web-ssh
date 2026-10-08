const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function setup(overrides = {}, systems = ['linux']) {
    const values = {commandFormName: 'List', commandFormCommand: 'ls', commandFormParams: '', commandFormDescription: 'List files', commandFormCategory: 'custom', ...overrides};
    const notifications = [];
    const emitted = [];
    const elements = {};
    const handlers = {};
    const confirmations = [];
    const window = {
        i18n: {t: key => `localized:${key}`},
        showNotification: message => notifications.push(message),
        socket: {emit: (...args) => emitted.push(args), on: (event, handler) => { handlers[event] = handler; }},
        ModalManager: {open() {}},
    };
    const document = {
        getElementById: id => elements[id] ||= {value: values[id], appendChild(child) { this.textContent = child.textContent; }},
        createElement: () => ({}),
        querySelectorAll: () => systems.map(value => ({value})),
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../static/js/command-library.js'), 'utf8'), {
        window, document, confirm: message => { confirmations.push(message); return false; },
    });
    return {library: window.CommandLibrary, window, notifications, emitted, elements, handlers, confirmations};
}

test('missing command fields show localized validation without sending', () => {
    const state = setup({commandFormName: ''});
    state.library.saveCommand();
    assert.deepEqual(state.notifications, ['localized:commands.requiredFields']);
    assert.equal(state.emitted.length, 0);
});

test('missing operating system shows localized validation without sending', () => {
    const state = setup({}, []);
    state.library.saveCommand();
    assert.deepEqual(state.notifications, ['localized:commands.osRequired']);
    assert.equal(state.emitted.length, 0);
});

test('failed command save retains the form and reports a localized error', () => {
    const state = setup();
    let closed = false;
    state.library.closeCommandForm = () => { closed = true; };
    state.library.saveCommand();
    state.emitted[0][2]({success: false, error: 'Failed to add command'});
    assert.deepEqual(state.notifications, ['localized:commands.saveFailed']);
    assert.equal(closed, false);
});

test('command success notifications use the active language', () => {
    const state = setup();
    state.library.loadCommands = () => {};
    state.library.setupEventListeners = () => {};
    state.library.init();
    for (const event of ['added', 'updated', 'deleted']) state.handlers[`command_${event}`]();
    assert.deepEqual(state.notifications, ['localized:commands.added', 'localized:commands.updated', 'localized:commands.deleted']);
});

test('add copy and edit form titles are translated', () => {
    const state = setup();
    state.library.commands = [{id: 'one', name: 'ls', command: 'ls', os: ['linux']}];
    state.library.showAddCommandForm();
    assert.equal(state.elements.commandFormTitle.textContent, 'localized:commands.addCommand');
    state.library.copyCommand('one');
    assert.equal(state.elements.commandFormTitle.textContent, 'localized:commands.copyToMine');
    state.library.editCommand('one');
    assert.equal(state.elements.commandFormTitle.textContent, 'localized:commands.editCommand');
});

test('delete confirmation translates the prompt and preserves the literal command name', () => {
    const state = setup();
    state.window.i18n.t = key => key === 'commands.deleteConfirm' ? 'Löschen: {name}?' : key;
    state.library.commands = [{id: 'one', name: '$& command'}];
    state.library.deleteCommand('one');
    assert.deepEqual(state.confirmations, ['Löschen: $& command?']);
    assert.equal(state.emitted.length, 0);
});

test('library OS filter keeps the shared catalog and combines search across catalog refreshes', () => {
    const state = setup();
    state.library.renderCommandsList = () => {};
    const commands = [
        {id: 'linux', name: 'Linux status', os: ['linux']},
        {id: 'win', name: 'Windows status', os: ['Windows']},
        {id: 'all', name: 'Common status', os: ['all']},
    ].map(command => ({command: '', parameters: '', description: '', category: 'custom', ...command}));
    state.library.currentOs = 'windows';
    state.library.setCommands(commands);
    assert.deepEqual(Array.from(state.library.commands, command => command.id), ['linux', 'win', 'all']);
    assert.deepEqual(Array.from(state.library.filteredCommands, command => command.id), ['win', 'all']);
    state.library.searchCommands('Windows');
    state.library.setCommands(commands);
    assert.deepEqual(Array.from(state.library.filteredCommands, command => command.id), ['win']);
    state.library.searchCommands('');
    assert.deepEqual(Array.from(state.library.filteredCommands, command => command.id), ['win', 'all']);
    state.library.loadCommands();
    assert.equal(state.emitted.at(-1)[1].os_filter, null);
});

test('empty library uses existing translations in all six languages', () => {
    const state = setup();
    const context = vm.createContext({
        window: state.window, document: {addEventListener() {}},
    });
    vm.runInContext(fs.readFileSync(path.join(__dirname, '../../static/js/i18n.js'), 'utf8'), context);
    // Register the lazy language bundles the way fetchI18nBundle would.
    for (const language of ['de', 'vi', 'fr', 'es', 'zh']) {
        const table = JSON.parse(fs.readFileSync(
            path.join(__dirname, `../../static/js/i18n/${language}.json`), 'utf8'));
        context.__bundleTable = table;
        vm.runInContext(
            `Object.assign(translations, { ${language}: __bundleTable });`,
            context,
        );
    }
    const expected = {en: 'No commands found', de: 'Keine Befehle gefunden', vi: 'Không tìm thấy lệnh', fr: 'Aucune commande trouvée', es: 'No se encontraron comandos', zh: '未找到命令'};
    for (const [language, text] of Object.entries(expected)) {
        state.window.i18n.currentLang = language;
        state.library.renderCommandsList();
        assert.equal(state.elements.commandsList.textContent, text);
    }
});
