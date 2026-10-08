/*
 * Session monitor sidebar: a compact live view of the active SSH host
 * (CPU/load, memory and swap, network throughput, per-mount disks, and the
 * top-CPU processes), rendered from the same session_insights samples the
 * diagnostics drawer consumes. All dynamic values go through textContent.
 */
(function (root, factory) {
    const api = factory();
    if (typeof module === 'object' && module.exports) {
        module.exports = api;
    }
    if (root && root.document) {
        root.SessionMonitorModule = api;
    }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';

    function nonNegativeNumber(value) {
        if (value === null || value === undefined || value === '' || typeof value === 'boolean') {
            return null;
        }
        const number = Number(value);
        return Number.isFinite(number) && number >= 0 ? number : null;
    }

    function boundedPercent(value) {
        const number = nonNegativeNumber(value);
        return number !== null && number <= 100 ? number : null;
    }

    function formatKib(value) {
        const kib = nonNegativeNumber(value);
        if (kib === null) return '—';
        const mib = kib / 1024;
        if (mib < 1024) return `${mib.toFixed(1)} MB`;
        const gib = mib / 1024;
        if (gib < 1024) return `${gib.toFixed(2)} GB`;
        return `${(gib / 1024).toFixed(1)} TB`;
    }

    function formatRate(bytesPerSecond) {
        const bps = nonNegativeNumber(bytesPerSecond);
        if (bps === null) return '—';
        if (bps < 1024) return `${Math.round(bps)} B/s`;
        const kbps = bps / 1024;
        if (kbps < 1024) return `${kbps.toFixed(1)} KB/s`;
        const mbps = kbps / 1024;
        if (mbps < 1024) return `${mbps.toFixed(1)} MB/s`;
        return `${(mbps / 1024).toFixed(2)} GB/s`;
    }

    function formatNumber(value, digits = 2) {
        const number = nonNegativeNumber(value);
        if (number === null) return '—';
        return number.toFixed(digits).replace(/\.?0+$/, '') || '0';
    }

    function percentUsed(used, total) {
        const usedValue = nonNegativeNumber(used);
        const totalValue = nonNegativeNumber(total);
        if (usedValue === null || totalValue === null || totalValue <= 0) return null;
        return Math.min(100, Math.round((usedValue / totalValue) * 100));
    }

    function severityForPercent(value) {
        const percent = Number(value);
        if (!Number.isFinite(percent)) return 'normal';
        if (percent >= 90) return 'critical';
        if (percent >= 75) return 'warning';
        return 'normal';
    }

    function shortCommand(command, maxLength = 24) {
        const text = String(command ?? '');
        if (!text) return '—';
        return text.length > maxLength
            ? `${text.slice(0, maxLength - 1)}…`
            : text;
    }

    const STATUS_LABELS = {
        ready: ['monitor.statusLive', 'Live'],
        loading: ['monitor.statusSampling', 'Sampling'],
        stale: ['monitor.statusStale', 'Stale'],
        unavailable: ['diagnostics.statusUnavailable', 'Unavailable'],
        reconnecting: ['workspace.toolsReconnecting', 'Reconnecting'],
        disconnected: ['monitor.statusOffline', 'Offline'],
    };

    function createController(options = {}) {
        const documentRef = options.document || document;
        const translate = typeof options.translate === 'function'
            ? options.translate
            : (key, fallback) => fallback || key;

        function tr(key, fallback) {
            const candidate = translate(key);
            return candidate && candidate !== key ? candidate : (fallback || key);
        }

        const panel = documentRef.getElementById('contextMonitorPanel');
        if (!panel) return null;

        panel.classList.add('session-monitor-panel');
        panel.innerHTML = (
            '<div class="session-monitor" id="sessionMonitorRoot">'
            + '  <div class="session-monitor-header">'
            + '    <div class="session-monitor-hostname" id="sessionMonitorHostname">—</div>'
            + '    <div class="session-monitor-osline" id="sessionMonitorOs"></div>'
            + '    <div class="session-monitor-statusline">'
            + '      <span class="session-monitor-status" id="sessionMonitorStatus"></span>'
            + '      <span class="session-monitor-updated" id="sessionMonitorUpdated"></span>'
            + '    </div>'
            + '  </div>'
            + '  <div class="session-monitor-body" id="sessionMonitorBody"></div>'
            + '  <div class="session-monitor-empty" id="sessionMonitorEmpty"></div>'
            + '</div>'
        );

        const hostEl = panel.querySelector('#sessionMonitorHostname');
        const osEl = panel.querySelector('#sessionMonitorOs');
        const statusEl = panel.querySelector('#sessionMonitorStatus');
        const updatedEl = panel.querySelector('#sessionMonitorUpdated');
        const bodyEl = panel.querySelector('#sessionMonitorBody');
        const emptyEl = panel.querySelector('#sessionMonitorEmpty');

        let currentSessionId = null;

        function setStatus(status) {
            const [key, fallback] = STATUS_LABELS[status] || STATUS_LABELS.disconnected;
            statusEl.textContent = tr(key, fallback);
            statusEl.className = `session-monitor-status is-${status}`;
        }

        function card(className, titleKey, titleFallback) {
            const section = documentRef.createElement('section');
            section.className = `monitor-card ${className}`;
            const heading = documentRef.createElement('h3');
            heading.className = 'monitor-card-title';
            heading.textContent = tr(titleKey, titleFallback);
            section.appendChild(heading);
            return section;
        }

        function meterRow(labelText, percent, captionText) {
            const row = documentRef.createElement('div');
            row.className = 'monitor-meter';
            const severity = severityForPercent(percent);
            const head = documentRef.createElement('div');
            head.className = 'monitor-meter-head';
            const label = documentRef.createElement('span');
            label.textContent = labelText;
            const value = documentRef.createElement('span');
            value.className = `monitor-meter-value is-${severity}`;
            value.textContent = percent === null ? '—' : `${Math.round(percent)}%`;
            head.appendChild(label);
            head.appendChild(value);
            const bar = documentRef.createElement('div');
            bar.className = 'monitor-meter-bar';
            const fill = documentRef.createElement('div');
            fill.className = `monitor-meter-fill is-${severity}`;
            fill.style.width = `${percent === null ? 0 : Math.max(2, Math.min(100, percent))}%`;
            bar.appendChild(fill);
            const caption = documentRef.createElement('div');
            caption.className = 'monitor-meter-caption';
            caption.textContent = captionText;
            row.appendChild(head);
            row.appendChild(bar);
            row.appendChild(caption);
            return row;
        }

        function renderCpuCard(stats, cpuPercent) {
            const cardEl = card('monitor-card-cpu', 'monitor.cpuTitle', 'CPU');
            const gaugeWrap = documentRef.createElement('div');
            gaugeWrap.className = 'monitor-cpu-row';
            const percentValue = boundedPercent(cpuPercent);
            const gauge = documentRef.createElement('div');
            gauge.className = 'monitor-cpu-gauge';
            const ring = documentRef.createElementNS('http://www.w3.org/2000/svg', 'svg');
            ring.setAttribute('viewBox', '0 0 84 84');
            ring.setAttribute('role', 'img');
            ring.setAttribute('aria-label', `${tr('monitor.cpuTitle', 'CPU')} ${percentValue ?? '—'}%`);
            const circleBg = documentRef.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circleBg.setAttribute('cx', '42');
            circleBg.setAttribute('cy', '42');
            circleBg.setAttribute('r', '34');
            circleBg.setAttribute('class', 'monitor-gauge-track');
            const circle = documentRef.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('cx', '42');
            circle.setAttribute('cy', '42');
            circle.setAttribute('r', '34');
            circle.setAttribute('class', `monitor-gauge-value is-${severityForPercent(percentValue ?? 0)}`);
            const circumference = 2 * Math.PI * 34;
            const shown = percentValue ?? 0;
            circle.setAttribute('stroke-dasharray', `${(circumference * shown) / 100} ${circumference}`);
            ring.appendChild(circleBg);
            ring.appendChild(circle);
            const gaugeLabel = documentRef.createElement('div');
            gaugeLabel.className = 'monitor-gauge-label';
            const gaugeValue = documentRef.createElement('div');
            gaugeValue.className = 'monitor-gauge-value';
            gaugeValue.textContent = percentValue === null ? '—' : `${Math.round(percentValue)}%`;
            const gaugeRange = documentRef.createElement('div');
            gaugeRange.className = 'monitor-gauge-range';
            gaugeRange.textContent = '0 - 100%';
            gaugeLabel.appendChild(gaugeValue);
            gaugeLabel.appendChild(gaugeRange);
            gauge.appendChild(ring);
            gauge.appendChild(gaugeLabel);
            gaugeWrap.appendChild(gauge);

            const facts = documentRef.createElement('div');
            facts.className = 'monitor-cpu-facts';
            const coreCount = nonNegativeNumber(stats?.load?.cpu_count);
            const factCores = documentRef.createElement('div');
            factCores.className = 'monitor-cpu-fact';
            const coresLabel = documentRef.createElement('span');
            coresLabel.textContent = tr('monitor.cores', 'Cores');
            const coresValue = documentRef.createElement('strong');
            coresValue.textContent = coreCount === null ? '—' : String(coreCount);
            factCores.appendChild(coresLabel);
            factCores.appendChild(coresValue);
            const factLoad = documentRef.createElement('div');
            factLoad.className = 'monitor-cpu-fact';
            factLoad.textContent = `${tr('monitor.load', 'Load')} ${formatNumber(stats?.load?.one)} / ${formatNumber(stats?.load?.five)}`;
            const factLoad15 = documentRef.createElement('div');
            factLoad15.className = 'monitor-cpu-fact monitor-cpu-fact-muted';
            factLoad15.textContent = `1/5/15  ${formatNumber(stats?.load?.fifteen)}`;
            facts.appendChild(factCores);
            facts.appendChild(factLoad);
            facts.appendChild(factLoad15);
            gaugeWrap.appendChild(facts);
            cardEl.appendChild(gaugeWrap);
            return cardEl;
        }

        function renderMemoryCard(stats) {
            const cardEl = card('monitor-card-memory', 'monitor.memory', 'Memory');
            const memory = stats?.memory;
            const swap = stats?.swap;
            const used = nonNegativeNumber(memory?.used_kib);
            const total = nonNegativeNumber(memory?.total_kib);
            const memoryPercent = percentUsed(used, total);
            const caption = `${formatKib(used)} / ${formatKib(total)}`;
            cardEl.appendChild(meterRow(tr('monitor.memory', 'Memory'), memoryPercent, caption));
            if (swap && nonNegativeNumber(swap.total_kib) > 0) {
                const swapPercent = percentUsed(swap.used_kib, swap.total_kib);
                cardEl.appendChild(meterRow(
                    tr('monitor.swap', 'Swap'),
                    swapPercent,
                    `${formatKib(swap.used_kib)} / ${formatKib(swap.total_kib)}`,
                ));
            }
            return cardEl;
        }

        function renderNetworkCard(networkRates) {
            const cardEl = card('monitor-card-network', 'monitor.network', 'Network');
            const row = documentRef.createElement('div');
            row.className = 'monitor-network-row';
            const up = documentRef.createElement('div');
            up.className = 'monitor-network-item is-up';
            const upIcon = documentRef.createElement('span');
            upIcon.className = 'material-icons';
            upIcon.setAttribute('aria-hidden', 'true');
            upIcon.textContent = 'arrow_upward';
            up.appendChild(upIcon);
            up.appendChild(documentRef.createTextNode(formatRate(networkRates?.transmitted_bps)));
            const down = documentRef.createElement('div');
            down.className = 'monitor-network-item is-down';
            const downIcon = documentRef.createElement('span');
            downIcon.className = 'material-icons';
            downIcon.setAttribute('aria-hidden', 'true');
            downIcon.textContent = 'arrow_downward';
            down.appendChild(downIcon);
            down.appendChild(documentRef.createTextNode(formatRate(networkRates?.received_bps)));
            row.appendChild(up);
            row.appendChild(down);
            cardEl.appendChild(row);
            return cardEl;
        }

        function renderDisksCard(stats) {
            const mounts = Array.isArray(stats?.disks) && stats.disks.length
                ? stats.disks
                : (stats?.disk ? [stats.disk] : []);
            if (!mounts.length) return null;
            const cardEl = card('monitor-card-disks', 'monitor.disks', 'Disks');
            mounts.slice(0, 8).forEach((entry) => {
                const mountName = entry.mount ?? '/';
                const percent = entry.percent ?? percentUsed(entry.used_kib, entry.total_kib);
                const caption = `${formatKib(entry.used_kib)}/${formatKib(entry.total_kib)}`;
                cardEl.appendChild(meterRow(mountName, boundedPercent(percent), caption));
            });
            return cardEl;
        }

        function renderProcessesCard(stats) {
            const topCpu = Array.isArray(stats?.processes?.top_cpu)
                ? stats.processes.top_cpu
                : [];
            if (!topCpu.length) return null;
            const cardEl = card(
                'monitor-card-processes',
                'monitor.topProcesses',
                'Top Processes (CPU)',
            );
            const table = documentRef.createElement('table');
            table.className = 'monitor-process-table';
            const thead = documentRef.createElement('thead');
            const headRow = documentRef.createElement('tr');
            [
                ['monitor.processPid', 'PID'],
                ['monitor.processName', 'Process'],
                ['monitor.processCpu', 'CPU'],
                ['monitor.processMemory', 'Memory'],
            ].forEach(([key, fallback]) => {
                const th = documentRef.createElement('th');
                th.scope = 'col';
                th.textContent = tr(key, fallback);
                headRow.appendChild(th);
            });
            thead.appendChild(headRow);
            table.appendChild(thead);
            const tbody = documentRef.createElement('tbody');
            topCpu.slice(0, 7).forEach((entry) => {
                const row = documentRef.createElement('tr');
                const pid = documentRef.createElement('td');
                pid.textContent = String(entry.pid ?? '—');
                const name = documentRef.createElement('td');
                name.textContent = shortCommand(entry.command);
                name.title = String(entry.command ?? '');
                const cpu = documentRef.createElement('td');
                cpu.textContent = `${formatNumber(entry.cpu_percent, 1)}%`;
                const memory = documentRef.createElement('td');
                memory.textContent = `${formatNumber(entry.memory_percent, 1)}%`;
                row.appendChild(pid);
                row.appendChild(name);
                row.appendChild(cpu);
                row.appendChild(memory);
                tbody.appendChild(row);
            });
            table.appendChild(tbody);
            cardEl.appendChild(table);
            return cardEl;
        }

        function renderBody(state) {
            const stats = state?.stats;
            bodyEl.replaceChildren();
            const cards = [];
            if (stats && (stats.load || Array.isArray(stats.cpu))) {
                cards.push(renderCpuCard(stats, state?.cpuPercent));
            }
            if (stats && (stats.memory || stats.swap)) {
                cards.push(renderMemoryCard(stats));
            }
            if (stats && stats.network) {
                cards.push(renderNetworkCard(state?.networkRates));
            }
            const disksCard = renderDisksCard(stats);
            if (disksCard) cards.push(disksCard);
            const processesCard = renderProcessesCard(stats);
            if (processesCard) cards.push(processesCard);
            cards.forEach((cardEl) => bodyEl.appendChild(cardEl));
            const hasData = cards.length > 0;
            bodyEl.hidden = !hasData;
            emptyEl.hidden = hasData;
            if (!hasData) {
                emptyEl.textContent = state?.status === 'loading'
                    ? tr('monitor.sampling', 'Sampling the remote host…')
                    : tr('monitor.noData', 'No supported metrics are available for this host.');
            }
        }

        function render(state, session) {
            if (!state) return;
            if (state.sessionId && state.sessionId !== currentSessionId) {
                currentSessionId = state.sessionId;
            }
            const hostname = typeof state.stats?.hostname === 'string' && state.stats.hostname
                ? state.stats.hostname
                : (session?.host ? `${session.host}` : '—');
            hostEl.textContent = hostname;
            hostEl.title = session?.host ? `${session.username}@${session.host}:${session.port}` : '';
            const osName = typeof state.stats?.os_name === 'string' ? state.stats.os_name : '';
            osEl.textContent = osName;
            osEl.hidden = !osName;
            setStatus(state.status === 'ready' && !state.stats ? 'loading' : state.status);
            const updated = state.status === 'ready'
                ? new Date().toLocaleTimeString()
                : '';
            updatedEl.textContent = updated ? `${tr('monitor.updated', 'Updated')} ${updated}` : '';
            renderBody(state);
        }

        return {
            render,
            setVisible(nextVisible) {
                panel.hidden = !nextVisible;
            },
            setSession(sessionId) {
                currentSessionId = sessionId;
            },
            removeSession(sessionId) {
                if (sessionId === currentSessionId) {
                    currentSessionId = null;
                }
            },
        };
    }

    return {
        createController,
        formatKib,
        formatRate,
        formatNumber,
        percentUsed,
        severityForPercent,
        shortCommand,
    };
}));
