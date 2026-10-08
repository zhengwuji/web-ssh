const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync('static/js/i18n.js', 'utf8');

function loadI18n(localStorage, options = {}) {
    const document = {
        documentElement: {},
        title: '',
        addEventListener() {},
        querySelector() { return null; },
        querySelectorAll() { return []; },
    };
    const window = {
        localStorage,
        dispatchEvent() {},
    };
    const context = vm.createContext({
        CustomEvent: class CustomEvent {},
        document,
        window,
        fetch: options.fetch,
    });
    vm.runInContext(source, context);
    return window;
}

function bundleResponse(language) {
    const table = JSON.parse(
        fs.readFileSync(path.join(__dirname, `../../static/js/i18n/${language}.json`), 'utf8')
    );
    return () => Promise.resolve({ ok: true, json: () => Promise.resolve(table) });
}

test('unsupported stored languages fall back to English', () => {
    const window = loadI18n({
        getItem() { return 'unsupported'; },
        setItem() {},
    });

    assert.equal(window.i18n.getLanguage(), 'en');
    assert.equal(window.i18n.t('common.actions'), 'Actions');
});

test('blocked browser storage does not prevent translations from loading', async () => {
    const window = loadI18n({
        getItem() { throw new Error('storage denied'); },
        setItem() { throw new Error('storage denied'); },
    }, { fetch: bundleResponse('de') });

    assert.equal(window.i18n.getLanguage(), 'en');
    // Non-English tables load lazily; switching is accepted immediately and
    // applied once the bundle arrives.
    assert.equal(window.i18n.setLanguage('de'), true);
    assert.equal(window.i18n.getLanguage(), 'de');
    assert.equal(window.i18n.t('common.actions'), 'Actions');
    await window.i18n.ensureLanguage('de');
    assert.equal(window.i18n.t('common.actions'), 'Aktionen');
    assert.equal(window.BrowserPreferences.set('example', 'value'), false);
});
