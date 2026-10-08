/*
 * Server-injected page context.
 *
 * Replaces the former inline <script> data islands so the page can run under
 * a strict CSP (script-src 'self'): the template renders the values as JSON
 * data attributes on <body>, and this module promotes them to the globals
 * the rest of the app reads. Loaded before any app script.
 */
(function() {
    'use strict';

    function readJsonAttribute(name) {
        const raw = document.body ? document.body.getAttribute(name) : null;
        if (!raw) {
            return null;
        }
        try {
            return JSON.parse(raw);
        } catch {
            return null;
        }
    }

    const transferLimits = readJsonAttribute('data-transfer-limits');
    if (transferLimits && typeof transferLimits === 'object') {
        window.WEBSSH_TRANSFER_LIMITS = Object.freeze(transferLimits);
    }

    const sshInputLimits = readJsonAttribute('data-ssh-input-limits');
    if (sshInputLimits && typeof sshInputLimits === 'object') {
        window.WEBSSH_SSH_INPUT_LIMITS = Object.freeze(sshInputLimits);
    }

    document.addEventListener('DOMContentLoaded', () => {
        const flashed = readJsonAttribute('data-flashed-messages');
        if (!Array.isArray(flashed) || typeof window.showNotification !== 'function') {
            return;
        }
        flashed.forEach(([category, message]) => {
            const type = category === 'error' ? 'error'
                : (category === 'success' ? 'success' : 'info');
            window.showNotification(message, type);
        });
    });
})();
