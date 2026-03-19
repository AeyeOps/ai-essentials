import * as vscode from 'vscode';
import { SessionDiscovery, resolveTranscriptPath } from './sessionDiscovery.js';
import { StateDetector } from './stateDetector.js';
import { SessionsProvider } from './sessionsProvider.js';
import { SessionsWebviewProvider } from './sessionsWebviewProvider.js';
import { TerminalMapper } from './terminalMapper.js';
import { detectPlatform } from './platform.js';
import type { SessionState } from './types.js';

function createDetector(
  discovery: SessionDiscovery,
  providers: { refresh(): void },
  session: { pid: number; cwd: string; sessionId: string },
  log: vscode.LogOutputChannel,
): StateDetector {
  const filePath = resolveTranscriptPath(session.pid, session.cwd, session.sessionId);
  log.debug(`Creating detector: ${session.sessionId.slice(0, 8)} pid=${session.pid}`);
  const detector = new StateDetector(filePath, session.sessionId, session.pid, (_sid: string, state: SessionState, toolName?: string, toolDetail?: string) => {
    const s = discovery.getSession(_sid);
    if (s) {
      s.state = state;
      s.toolName = toolName;
      s.toolDetail = toolDetail;
      s.stateChangedAt = Date.now();
      providers.refresh();
    }
  }, log);
  detector.start();
  return detector;
}

export function activate(context: vscode.ExtensionContext): void {
  const log = vscode.window.createOutputChannel('aeo-vsc-cc-sessions', { log: true });
  context.subscriptions.push(log);

  const platform = detectPlatform();
  log.info(`Activated | Platform: ${platform.label} (proc=${platform.hasProc}) | Log: ${context.logUri.fsPath}`);

  if (!platform.hasProc) {
    const key = 'noProcDismissed';
    if (!context.globalState.get<boolean>(key)) {
      void vscode.window.showInformationMessage(
        'AEO VSC CC Sessions: /proc not available — session detection requires Linux or WSL.',
        'OK',
      ).then(() => void context.globalState.update(key, true));
    }
  }

  const discovery = new SessionDiscovery();
  const treeProvider = new SessionsProvider(discovery);
  const webviewProvider = new SessionsWebviewProvider(discovery);
  const terminalMapper = new TerminalMapper(discovery, log);
  treeProvider.setTerminalMapper(terminalMapper);
  webviewProvider.setTerminalMapper(terminalMapper);
  const detectors = new Map<string, StateDetector>();

  const bothProviders = {
    refresh() { treeProvider.refresh(); webviewProvider.refresh(); },
  };

  const treeView = vscode.window.createTreeView('aeoVscCcSessions', { treeDataProvider: treeProvider });

  const webviewReg = vscode.window.registerWebviewViewProvider('aeoVscCcSessionsRich', webviewProvider);

  const savedMode = context.globalState.get<string>('viewMode', 'tree');
  void vscode.commands.executeCommand('setContext', 'aeoVscCcSessions.viewMode', savedMode);

  const showTreeCmd = vscode.commands.registerCommand('aeoVscCcSessions.showTreeView', () => {
    void context.globalState.update('viewMode', 'tree');
    void vscode.commands.executeCommand('setContext', 'aeoVscCcSessions.viewMode', 'tree');
  });
  const showRichCmd = vscode.commands.registerCommand('aeoVscCcSessions.showRichView', () => {
    void context.globalState.update('viewMode', 'rich');
    void vscode.commands.executeCommand('setContext', 'aeoVscCcSessions.viewMode', 'rich');
    webviewProvider.refresh();
  });

  const focusCmd = vscode.commands.registerCommand('aeoVscCcSessions.focusSession', (sessionId: string) => {
    void terminalMapper.focusSession(sessionId);
  });

  const matchSub = terminalMapper.onDidMatch(() => bothProviders.refresh());

  function ensureDetector(session: { pid: number; cwd: string; sessionId: string }): void {
    if (!detectors.has(session.sessionId)) {
      detectors.set(session.sessionId, createDetector(discovery, bothProviders, session, log));
    }
  }

  const sessionSub = discovery.onDidChangeSession(event => {
    const { type, session } = event;

    if (type === 'added') {
      log.debug(`Session added: ${session.sessionId.slice(0, 8)} pid=${session.pid}`);
      if (session.state !== 'exited') {
        ensureDetector(session);
      }
      void terminalMapper.matchAll();
    } else if (type === 'removed') {
      log.debug(`Session removed: ${session.sessionId.slice(0, 8)}`);
      const detector = detectors.get(session.sessionId);
      if (detector) {
        detector.dispose();
        detectors.delete(session.sessionId);
      }
      bothProviders.refresh();
    } else {
      bothProviders.refresh();
    }
  });

  for (const [, session] of discovery.getSessions()) {
    if (session.state !== 'exited') {
      ensureDetector(session);
    }
  }

  void terminalMapper.matchAll();

  const refreshInterval = vscode.workspace.getConfiguration('aeoVscCcSessions').get<number>('refreshInterval', 3000);
  const periodicRefresh = setInterval(() => bothProviders.refresh(), refreshInterval);

  context.subscriptions.push(
    discovery,
    treeProvider,
    webviewProvider,
    terminalMapper,
    treeView,
    webviewReg,
    showTreeCmd,
    showRichCmd,
    focusCmd,
    sessionSub,
    matchSub,
    { dispose: () => clearInterval(periodicRefresh) },
    { dispose: () => { for (const d of detectors.values()) d.dispose(); detectors.clear(); } },
  );
}

export function deactivate(): void {}
