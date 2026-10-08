const assert = require('node:assert/strict');
const test = require('node:test');

const monitor = require('../../static/js/session-monitor.js');


test('formatKib renders MB, GB, and TB boundaries', () => {
    assert.equal(monitor.formatKib(undefined), '—');
    assert.equal(monitor.formatKib(336337), '328.5 MB');
    assert.equal(monitor.formatKib(38796288), '37.00 GB');
    assert.equal(monitor.formatKib(1024 * 1024 * 1024), '1.0 TB');
});

test('formatRate scales bytes per second', () => {
    assert.equal(monitor.formatRate(0), '0 B/s');
    assert.equal(monitor.formatRate(9625), '9.4 KB/s');
    assert.equal(monitor.formatRate(4198), '4.1 KB/s');
    assert.equal(monitor.formatRate(5 * 1024 * 1024), '5.0 MB/s');
});

test('formatNumber trims trailing zeros', () => {
    assert.equal(monitor.formatNumber(0.16), '0.16');
    assert.equal(monitor.formatNumber(2), '2');
    assert.equal(monitor.formatNumber(null), '—');
});

test('severityForPercent matches threshold bands', () => {
    assert.equal(monitor.severityForPercent(1), 'normal');
    assert.equal(monitor.severityForPercent(80), 'warning');
    assert.equal(monitor.severityForPercent(95), 'critical');
});

test('shortCommand bounds long process names', () => {
    assert.equal(monitor.shortCommand('sshd'), 'sshd');
    assert.equal(monitor.shortCommand('x'.repeat(40)).length, 24);
});

function elementStub(shared) {
    const classes = new Set();
    const bySelector = shared || new Map();
    return {
        className: '',
        textContent: '',
        innerHTML: '',
        hidden: false,
        title: '',
        style: {},
        children: [],
        setAttribute() {},
        getAttribute() { return null; },
        appendChild(child) { this.children.push(child); },
        addEventListener() {},
        querySelector(selector) {
            if (!bySelector.has(selector)) bySelector.set(selector, elementStub(bySelector));
            return bySelector.get(selector);
        },
        replaceChildren() { this.children = []; },
        classList: {
            add: name => classes.add(name),
            remove: name => classes.delete(name),
            toggle() {},
            contains: name => classes.has(name),
        },
    };
}

test('controller renders metric cards into the panel', () => {
    const panels = new Map();
    const shared = new Map();
    const documentStub = {
        getElementById(id) {
            if (!panels.has(id)) panels.set(id, elementStub(shared));
            return panels.get(id);
        },
        createElement: () => elementStub(new Map()),
        createElementNS: () => elementStub(new Map()),
        createTextNode: text => ({ textContent: text }),
    };
    const controller = monitor.createController({
        document: documentStub,
        translate: key => key,
    });
    assert.ok(controller, 'controller requires the panel element');

    controller.render({
        status: 'ready',
        sessionId: 'session-1',
        stats: {
            hostname: 'cool-laser-3.localdomain',
            os_name: 'Ubuntu 26.04.1 LTS',
            cpu: [100, 0, 200, 700, 0, 0, 0, 0],
            load: { one: 0.16, five: 0.11, fifteen: 0.09, cpu_count: 2 },
            memory: { total_kib: 2076320, available_kib: 1736000, used_kib: 340320 },
            swap: { total_kib: 4169724, available_kib: 4169724, used_kib: 0 },
            network: { received_bytes: 123456789, transmitted_bytes: 98765432 },
            disks: [
                { mount: '/', total_kib: 38796288, used_kib: 7106560, available_kib: 29698176, percent: 19 },
                { mount: '/boot', total_kib: 1403712, used_kib: 218624, available_kib: 1185088, percent: 16 },
            ],
            processes: {
                total: 154,
                zombies: 0,
                top_cpu: [
                    { pid: 1441, user: 'root', command: 'sshd', cpu_percent: 0.2, memory_percent: 0.3 },
                ],
                top_memory: [],
            },
        },
        cpuPercent: 1,
        networkRates: { received_bps: 4198, transmitted_bps: 9625 },
    }, { host: 'cool-laser-3.localdomain', username: 'root', port: 22 });

    const body = shared.get('#sessionMonitorBody');
    assert.ok(body, 'body mounted');
    assert.equal(body.children.length, 5, 'cpu, memory, network, disks, processes cards');
    const host = shared.get('#sessionMonitorHostname');
    assert.equal(host.textContent, 'cool-laser-3.localdomain');
});

test('controller shows the empty state without metrics', () => {
    const panels = new Map();
    const shared = new Map();
    const documentStub = {
        getElementById(id) {
            if (!panels.has(id)) panels.set(id, elementStub(shared));
            return panels.get(id);
        },
        createElement: () => elementStub(new Map()),
        createElementNS: () => elementStub(new Map()),
        createTextNode: text => ({ textContent: text }),
    };
    const controller = monitor.createController({
        document: documentStub,
        translate: key => key,
    });
    controller.render({ status: 'ready', sessionId: 's1', stats: {} }, null);
    const body = shared.get('#sessionMonitorBody');
    const empty = shared.get('#sessionMonitorEmpty');
    assert.equal(body.children.length, 0);
    assert.equal(empty.hidden, false);
});
