import * as vscode from 'vscode';
import { SessionDiscovery, resolveTranscriptPath } from './sessionDiscovery.js';
import { StateDetector } from './stateDetector.js';
import { SessionsProvider } from './sessionsProvider.js';
import { SessionsWebviewProvider } from './sessionsWebviewProvider.js';
import { TerminalMapper } from './terminalMapper.js';
import type { SessionState } from './types.js';

function createDetector(
  discovery: SessionDiscovery,
  providers: { refresh(): void },
  session: { pid: number; cwd: string; sessionId: string },
): StateDetector {
  const filePath = resolveTranscriptPath(session.pid, session.cwd, session.sessionId);
  log.appendLine(`createDetector: pid=${session.pid} sid=${session.sessionId.slice(0, 8)} path=${filePath}`);
  const detector = new StateDetector(filePath, session.sessionId, (sid: string, state: SessionState, toolName?: string, toolDetail?: string) => {
    log.appendLine(`stateChange: pid=${session.pid} state=${state} tool=${toolName ?? ''} detail=${toolDetail ?? ''}`);
    const s = discovery.getSession(sid);
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

const log = vscode.window.createOutputChannel('Claude Sessions');

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(log);
  const discovery = new SessionDiscovery();
  const treeProvider = new SessionsProvider(discovery);
  const webviewProvider = new SessionsWebviewProvider(discovery);
  const terminalMapper = new TerminalMapper(discovery);
  treeProvider.setTerminalMapper(terminalMapper);
  webviewProvider.setTerminalMapper(terminalMapper);
  const detectors = new Map<string, StateDetector>();

  const bothProviders = {
    refresh() { treeProvider.refresh(); webviewProvider.refresh(); },
  };

  const treeView = vscode.window.createTreeView('claudeSessions', { treeDataProvider: treeProvider });

  const webviewReg = vscode.window.registerWebviewViewProvider('claudeSessionsRich', webviewProvider);

  const savedMode = context.globalState.get<string>('viewMode', 'tree');
  log.appendLine(`viewMode: restoring saved=${savedMode}`);
  void vscode.commands.executeCommand('setContext', 'claudeSessions.viewMode', savedMode);

  const showTreeCmd = vscode.commands.registerCommand('claudeSessions.showTreeView', () => {
    void context.globalState.update('viewMode', 'tree');
    void vscode.commands.executeCommand('setContext', 'claudeSessions.viewMode', 'tree');
  });
  const showRichCmd = vscode.commands.registerCommand('claudeSessions.showRichView', () => {
    void context.globalState.update('viewMode', 'rich');
    void vscode.commands.executeCommand('setContext', 'claudeSessions.viewMode', 'rich');
    webviewProvider.refresh();
  });

  const refreshCmd = vscode.commands.registerCommand('claudeSessions.refresh', () => {
    void terminalMapper.matchAll().then(() => bothProviders.refresh());
  });
  const focusCmd = vscode.commands.registerCommand('claudeSessions.focusSession', (sessionId: string) => {
    log.appendLine(`focusSession called: sessionId=${sessionId}`);
    void terminalMapper.focusSession(sessionId, log);
  });

  const matchSub = terminalMapper.onDidMatch(() => bothProviders.refresh());

  function ensureDetector(session: { pid: number; cwd: string; sessionId: string }): void {
    if (!detectors.has(session.sessionId)) {
      detectors.set(session.sessionId, createDetector(discovery, bothProviders, session));
    }
  }

  const sessionSub = discovery.onDidChangeSession(event => {
    const { type, session } = event;

    if (type === 'added') {
      if (session.state !== 'exited') {
        ensureDetector(session);
      }
      void terminalMapper.matchAll();
    } else if (type === 'removed') {
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

  const refreshInterval = vscode.workspace.getConfiguration('claudeSessions').get<number>('refreshInterval', 3000);
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
    refreshCmd,
    focusCmd,
    sessionSub,
    matchSub,
    { dispose: () => clearInterval(periodicRefresh) },
    { dispose: () => { for (const d of detectors.values()) d.dispose(); detectors.clear(); } },
  );
}

export function deactivate(): void {}
