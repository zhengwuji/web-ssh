const test = require('node:test');
const assert = require('node:assert/strict');

function element() {
    return {
        id: '',
        className: '',
        innerHTML: '',
        textContent: '',
        value: '',
        attributes: {},
        listeners: {},
        classList: { add() {}, remove() {}, contains: () => false },
        setAttribute(name, value) { this.attributes[name] = value; },
        getAttribute(name) { return this.attributes[name]; },
        addEventListener(name, handler) { this.listeners[name] = handler; },
        querySelectorAll: () => [],
        reset() {},
        appendChild() {},
    };
}

const elements = {};
const opened = [];
const closed = [];
global.window = {
    ModalManager: {
        open(modal) { opened.push(modal); },
        close(modal) { closed.push(modal); },
    },
};
global.document = {
    getElementById: id => (elements[id] ||= element()),
    createElement: () => element(),
    body: { appendChild() {} },
};

require('../../static/js/sftp-file-manager.js');
const Manager = window.SFTPFileManager;

function fixture() {
    const emitted = [];
    const manager = Object.create(Manager.prototype);
    Object.assign(manager, {
        socket: { emit(...args) { emitted.push(args); } },
        quickHostKeyModal: null,
        quickHostKeyPrompt: null,
        qcModal: element(),
        modal: element(),
        gatewayQuickRequestId: null,
        pendingQuickConnectPane: null,
        pendingQuickConnectProfileId: null,
        t: (_key, fallback) => fallback,
    });
    manager.createQuickHostKeyModal();
    return { manager, emitted };
}

const prompt = {
    flow: 'quick',
    prompt_id: 'quick-prompt-1',
    host: 'target.example',
    port: 22,
    key_type: 'ssh-ed25519',
    fingerprint: 'SHA256:AbCdEf0123456789',
    context: 'target',
    client_request_id: null,
};

test('only well formed quick prompts open the quick host key dialog', () => {
    const { manager } = fixture();
    opened.length = 0;

    manager.handleQuickHostKeyPrompt({ ...prompt, flow: 'terminal' });
    manager.handleQuickHostKeyPrompt({ ...prompt, flow: undefined });
    manager.handleQuickHostKeyPrompt(null);
    assert.equal(manager.quickHostKeyPrompt, null);
    assert.deepEqual(opened, []);

    manager.handleQuickHostKeyPrompt({ ...prompt, prompt_id: 17 });
    manager.handleQuickHostKeyPrompt({ ...prompt, host: { toString: () => 'x' } });
    manager.handleQuickHostKeyPrompt({ ...prompt, key_type: undefined });
    manager.handleQuickHostKeyPrompt({ ...prompt, fingerprint: ['a'] });
    assert.equal(manager.quickHostKeyPrompt, null);
    assert.deepEqual(opened, []);

    manager.handleQuickHostKeyPrompt(prompt);
    assert.deepEqual(manager.quickHostKeyPrompt, { promptId: 'quick-prompt-1' });
    assert.equal(
        elements.fmQuickHostKeyTarget.textContent,
        'Target: target.example · ssh-ed25519',
    );
    assert.equal(
        elements.fmQuickHostKeyFingerprint.textContent,
        'SHA256:AbCdEf0123456789',
    );
    assert.equal(opened.length, 1);
    assert.equal(opened[0], manager.quickHostKeyModal);
});

test('answering the prompt closes it first and emits only the decision', () => {
    const { manager, emitted } = fixture();
    closed.length = 0;
    manager.handleQuickHostKeyPrompt(prompt);

    manager.answerQuickHostKeyPrompt(true);

    assert.equal(manager.quickHostKeyPrompt, null);
    assert.equal(closed.length, 1);
    assert.deepEqual(emitted, [[
        'ssh_host_key_decision',
        { prompt_id: 'quick-prompt-1', accepted: true },
    ]]);

    manager.answerQuickHostKeyPrompt(false);
    assert.equal(emitted.length, 1, 'a stale answer must not be replayed');
});

test('a rejected prompt is answered with an explicit denial', () => {
    const { manager, emitted } = fixture();
    manager.handleQuickHostKeyPrompt(prompt);

    manager.answerQuickHostKeyPrompt(false);

    assert.deepEqual(emitted, [[
        'ssh_host_key_decision',
        { prompt_id: 'quick-prompt-1', accepted: false },
    ]]);
    assert.equal(manager.quickHostKeyPrompt, null);
});

test('any non true answer is normalised to a denial', () => {
    for (const answer of [undefined, null, 0, 1, 'true', {}]) {
        const { manager, emitted } = fixture();
        manager.handleQuickHostKeyPrompt(prompt);
        manager.answerQuickHostKeyPrompt(answer);
        assert.deepEqual(emitted[0][1].accepted, answer === true);
    }
});

test('the decision payload never carries the fingerprint or the target', () => {
    const { manager, emitted } = fixture();
    manager.handleQuickHostKeyPrompt(prompt);
    manager.answerQuickHostKeyPrompt(true);

    const serialized = JSON.stringify(emitted);
    assert.equal(serialized.includes('SHA256:AbCdEf0123456789'), false);
    assert.equal(serialized.includes('target.example'), false);
});

test('closing the dialog without a pending prompt emits nothing', () => {
    const { manager, emitted } = fixture();

    assert.equal(manager.closeQuickHostKeyPrompt(), false);
    assert.equal(manager.closeQuickHostKeyPrompt(), false);
    assert.equal(manager.quickHostKeyPrompt, null);
    assert.deepEqual(emitted, []);
});

test('closing the quick connect form denies an outstanding host key prompt', () => {
    const { manager, emitted } = fixture();
    manager.handleQuickHostKeyPrompt(prompt);

    manager.closeQuickConnect();

    assert.deepEqual(emitted, [[
        'ssh_host_key_decision',
        { prompt_id: 'quick-prompt-1', accepted: false },
    ]]);
    assert.equal(manager.quickHostKeyPrompt, null);
});
