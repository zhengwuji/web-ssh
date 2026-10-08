(function (root) {
    'use strict';

    function init(options) {
        const socket = options.socket;
        const sessionManager = options.sessionManager;
        const terminalManager = options.terminalManager;
        const documentRef = options.document || document;
        const insightsModule = root.SessionInsightsModule;
        const diagnosticsModule = root.SessionDiagnosticsModule;
        const inventoryModule = root.SessionRuntimeInventoryModule;
        const chartsModule = root.SessionDiagnosticsCharts;
        const monitorModule = root.SessionMonitorModule;
        const filesModule = root.SessionFilesPanelModule;
        const workspaceModule = root.SessionWorkspaceModule;
        const fileManager = root.getSFTPFileManager?.();
        if (!socket || !sessionManager || !insightsModule || !diagnosticsModule || !inventoryModule || !chartsModule || !filesModule || !workspaceModule || !fileManager) {
            return null;
        }

        const elements = {
            filesPanel: documentRef.getElementById('sessionFilesPanel'),
            filesTab: documentRef.getElementById('contextFilesTab'),
            filesMount: documentRef.getElementById('sessionFilesMount'),
            filesStatus: documentRef.getElementById('sessionFilesStatus'),
        };
        if (!elements.filesTab || !elements.filesPanel || !elements.filesMount) return null;

        let filesController = null;
        let coordinator = null;
        let insightsController = null;
        let monitorController = null;
        let inventoryController = null;
        let diagnosticsController = null;
        let lastInsightsState = { status: 'disconnected', sessionId: null };
        let lastInventoryState = { status: 'disconnected', sessionId: null, inventory: null };
        let inventorySessionId = null;
        let inventoryConnected = false;
        let transportReady = socket.connected !== false;
        let fitScheduled = false;
        const directorySync = root.SessionDirectorySync?.createController({
            socket,
            manager: fileManager,
            enabledByDefault: documentRef.body?.dataset?.syncTerminalDirectory !== 'false',
            indicator: documentRef.getElementById('sessionDirectorySyncIndicator'),
            input: documentRef.getElementById('sessionDirectorySyncInput'),
            panel: elements.filesPanel,
            sendInput: (id, value) => root.SSHInput.send(id, value),
            hasPendingInput: id => root.SSHInput?.hasPending(id),
            onNavigationBlocked: reason => {
                const messages = {
                    prompt: ['workspace.directorySync.prompt', 'Folder sync paused: an empty terminal prompt could not be confirmed. Finish your input, or turn off sync to browse Files independently.'],
                    unavailable: ['workspace.directorySync.unavailable', 'The terminal folder could not be checked. Leave tmux copy mode or the running application and try again.'],
                    pending: ['workspace.directorySync.pending', 'The previous folder change is still being checked. Please try again shortly.'],
                };
                const [key, fallback] = messages[reason] || messages.unavailable;
                const translated = root.i18n?.t(key);
                root.showNotification?.(translated && translated !== key ? translated : fallback, 'info');
            },
        });
        fileManager.onDirectorySyncNavigate = (id, path) => directorySync?.navigate(id, path);

        function selectedContext() {
            return root.workspaceLayoutController?.getState?.().activeContext || null;
        }

        function syncInsightsVisibility() {
            const activeContext = selectedContext();
            coordinator.setVisible(
                documentRef.visibilityState !== 'hidden'
                && (
                    (activeContext === 'diagnostics'
                        && diagnosticsController?.isOpen())
                    || activeContext === 'monitor'
                )
            );
        }

        function syncDirectoryContext() {
            const id = sessionManager.getWorkspaceSession?.()
                || sessionManager.getActiveSession();
            directorySync?.setContext(
                transportReady && sessionManager.getSession(id)?.connected ? id : null,
                documentRef.visibilityState !== 'hidden'
                    && selectedContext() === 'files'
                    && documentRef.body?.dataset?.primaryWorkspace === 'workspaces'
                    && fileManager.isEmbeddedOpen(),
            );
        }

        function syncContextControllers(activeContext = selectedContext()) {
            if (activeContext === 'files') coordinator?.openSftpPanel?.();
            diagnosticsController?.setOpen(activeContext === 'diagnostics');
            if (coordinator) syncInsightsVisibility();
            syncDirectoryContext();
        }

        function applySessionContextDefault(state = coordinator?.getState?.()) {
            const session = state?.sessionId
                ? sessionManager.getSession(state.sessionId)
                : null;
            if (!session?.connected || session.restored === true) return false;
            let sftpAvailable = null;
            if (state.sftpCapability === 'available') sftpAvailable = true;
            if (['unavailable', 'inconclusive'].includes(state.sftpCapability)) {
                sftpAvailable = false;
            }
            return root.workspaceLayoutController?.selectSessionDefault?.({
                sessionId: state.sessionId,
                sftpAvailable,
            }) || false;
        }

        function renderInsights(state) {
            lastInsightsState = state;
            const osName = state?.stats?.os_name;
            if (state?.sessionId && typeof osName === 'string' && osName.trim()) {
                root.WEBSSH_TARGET_OS_BY_SESSION ||= {};
                root.WEBSSH_TARGET_OS_BY_SESSION[state.sessionId] = osName.trim();
                root.dispatchEvent?.(new CustomEvent('session-target-os-change', {
                    detail: { sessionId: state.sessionId, osName: osName.trim() },
                }));
            }
            const active = sessionManager.getSession(state.sessionId);
            diagnosticsController?.render(
                !transportReady && active?.connected ? { ...state, status: 'reconnecting' } : state,
                active, lastInventoryState,
            );
            monitorController?.render(
                !transportReady && active?.connected ? { ...state, status: 'reconnecting' } : state,
                active,
            );
            root.workspaceLayoutController?.setContextAvailability?.(
                'monitor', Boolean(active?.connected)
            );
            applySessionContextDefault();
            syncContextControllers();
        }

        filesController = filesModule.createController({
            manager: fileManager,
            container: elements.filesMount,
            status: elements.filesStatus,
            translate(key, fallback) {
                return root.i18n?.t?.(key) || fallback;
            },
        });
        diagnosticsController = diagnosticsModule.createController({
            document: documentRef,
            window: root,
            inventoryModule,
            chartModule: chartsModule,
            onRefreshInventory() {
                inventoryController?.refresh();
                insightsController?.refresh();
            },
            onOpenChange(open) {
                insightsController?.setDiagnosticsVisible(open);
                inventoryController?.setOpen(open);
                syncInsightsVisibility();
            },
        });
        inventoryController = inventoryModule.createController({
            socket,
            render(state) {
                lastInventoryState = state;
                const active = sessionManager.getSession(lastInsightsState.sessionId);
                diagnosticsController?.render(
                    !transportReady && active?.connected ? { ...lastInsightsState, status: 'reconnecting' } : lastInsightsState,
                    active, lastInventoryState,
                );
            },
        });
        insightsController = insightsModule.createController({ socket, render: renderInsights });
        monitorController = monitorModule ? monitorModule.createController({
            document: documentRef,
            window: root,
            translate(key) {
                return root.i18n?.t?.(key);
            },
        }) : null;
        const wideDesktopQuery = root.matchMedia('(min-width: 1440px)');
        const sftpCapabilityTracker = workspaceModule.createSftpCapabilityTracker({
            socket,
            onChange: sync,
        });
        coordinator = workspaceModule.createCoordinator({
            filesPanel: filesController,
            insights: insightsController,
            isWideDesktop: () => wideDesktopQuery.matches,
            render(state) {
                // Render the coordinator snapshot before availability changes can
                // synchronously activate Files and trigger a nested, newer render.
                // Otherwise the stale outer snapshot can hide an already-mounted
                // SFTP workspace until the user changes tabs.
                elements.filesPanel.classList.toggle('hidden', !state.filesAvailable);
                root.workspaceLayoutController?.setContextAvailability?.(
                    'files', state.filesAvailable
                );
                sftpCapabilityTracker.probeIfNeeded(state);
                applySessionContextDefault(state);
                // Context updates can nest during restoration. Fit once per frame
                // and send only changed dimensions, leaving room for tool requests.
                if (fitScheduled) return;
                fitScheduled = true;
                root.requestAnimationFrame(() => {
                    fitScheduled = false;
                    terminalManager?.fitAndSyncVisibleTerminals?.({
                        socket,
                        isConnected: sessionId => Boolean(
                            sessionManager.getSession(sessionId)?.connected
                        ),
                        force: false,
                    });
                });
            },
        });

        function sync() {
            const activeId = sessionManager.getWorkspaceSession?.()
                || sessionManager.getActiveSession();
            const activeSession = activeId ? sessionManager.getSession(activeId) : null;
            const connected = Boolean(transportReady && activeId && activeSession?.connected);
            coordinator.update({
                layout: sessionManager.layout,
                sessionId: activeId,
                session: activeSession,
                transportReady,
                sessionCount: sessionManager.getAllSessions().length,
                sftpCapability: sftpCapabilityTracker.get(activeId),
            });
            filesController.setTransportReady?.(transportReady);
            syncContextControllers();
            if (activeId !== inventorySessionId || connected !== inventoryConnected) {
                inventorySessionId = activeId || null;
                inventoryConnected = connected;
                inventoryController.setSession(inventorySessionId, inventoryConnected);
            }
        }

        documentRef.addEventListener('session-sftp-request-close', event => {
            if (coordinator.getState().sftpOpen) coordinator.toggleSftp();
            if (root.workspaceLayoutController?.getState?.().activeContext === 'files') {
                root.workspaceLayoutController.closeContext(
                    event.detail?.reason === 'user' ? 'user' : 'programmatic'
                );
            }
        });

        documentRef.addEventListener('workspace-context-change', event => {
            syncContextControllers(event.detail?.activeContext || null);
        });
        root.addEventListener('primary-workspace-change', syncDirectoryContext);
        socket.on('disconnect', () => {
            transportReady = false;
            sync();
        });
        socket.on('connected', data => {
            if (data?.status !== 'success') return;
            transportReady = true;
            sync();
        });
        root.addEventListener('session-workspace-change', sync);
        root.addEventListener('session-removed', event => {
            const removedSessionId = event?.detail?.sessionId;
            directorySync?.removeSession(removedSessionId);
            insightsController?.removeSession(removedSessionId);
            monitorController?.removeSession(removedSessionId);
            inventoryController?.removeSession(removedSessionId);
            sftpCapabilityTracker.remove(removedSessionId);
            coordinator.removeSession(removedSessionId);
        });
        documentRef.addEventListener('visibilitychange', () => {
            syncInsightsVisibility();
            syncDirectoryContext();
        });
        wideDesktopQuery.addEventListener?.('change', sync);
        root.addEventListener('themeChanged', () => {
            diagnosticsController?.redraw();
        });
        syncContextControllers();
        sync();
        return coordinator;
    }

    root.SessionWorkspaceUI = { init };
}(window));
