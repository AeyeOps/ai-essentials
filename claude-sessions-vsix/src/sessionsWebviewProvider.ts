import * as vscode from 'vscode';
import * as path from 'node:path';
import type { SessionInfo, SessionState } from './types.js';
import type { SessionDiscovery } from './sessionDiscovery.js';
import type { TerminalMapper } from './terminalMapper.js';

function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  if (totalSeconds < 60) return `${totalSeconds}s`;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes < 60) return `${minutes}m ${seconds}s`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m`;
}

const stateSortOrder: Record<SessionState, number> = {
  tool: 0, thinking: 1, permission: 2, compact: 3, idle: 4, error: 5, exited: 6,
};

function getStatusText(session: SessionInfo): string {
  const elapsed = Date.now() - session.stateChangedAt;
  switch (session.state) {
    case 'idle': return `Idle ${formatDuration(elapsed)}`;
    case 'thinking': return elapsed > 3000 ? `Thinking ${formatDuration(elapsed)}...` : 'Thinking...';
    case 'tool':
      if (session.toolName && session.toolDetail) return `${session.toolName}: ${session.toolDetail}`;
      return session.toolName ?? 'Tool';
    case 'permission': return 'Waiting for permission...';
    case 'compact': return 'Compacting context...';
    case 'error': return 'Error';
    case 'exited': return 'Exited';
  }
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function getNonce(): string {
  let text = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return text;
}

const CSS = `
body { margin:0; padding:0; font-family: var(--vscode-font-family, system-ui); background: var(--vscode-sideBar-background, #181818); color: var(--vscode-foreground, #ccc); overflow-x:hidden; }
.row { padding:3px 6px 3px 0; cursor:pointer; border-left:3px solid transparent; line-height:1.2; }
.row:hover { background: var(--vscode-list-hoverBackground, #2a2d30); }
.r1 { display:flex; align-items:center; gap:5px; font-size:11px; padding-left:4px; }
.dot { width:7px; height:7px; border-radius:50%; flex-shrink:0; }
.name { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.status { margin-left:16px; font-size:10px; line-height:1.2; }
.empty { padding:12px; font-size:11px; color: var(--vscode-descriptionForeground, #888); }

.s-idle .dot { background:#3fb950; box-shadow:0 0 3px #3fb95055; }
.s-idle .status { color:#3fb950; }
.s-idle { border-left-color:#3fb950; }

.s-thinking .dot { background:#d29922; box-shadow:0 0 3px #d2992255; animation:pulse 1.5s ease-in-out infinite; }
.s-thinking .status { color:#d29922; }
.s-thinking { border-left-color:#d29922; }

.s-tool .dot { background:#58a6ff; box-shadow:0 0 3px #58a6ff55; }
.s-tool .status { color:#58a6ff; }
.s-tool { border-left-color:#58a6ff; }

.s-permission .dot { background:#f85149; box-shadow:0 0 3px #f8514955; }
.s-permission .status { color:#f85149; }
.s-permission { border-left-color:#f85149; }

.s-error .dot { background:#f85149; box-shadow:0 0 3px #f8514955; }
.s-error .status { color:#f85149; }
.s-error { border-left-color:#f85149; }

.s-compact .dot { background:#d29922; box-shadow:0 0 3px #d2992255; }
.s-compact .status { color:#d29922; }
.s-compact { border-left-color:#d29922; }

.s-exited .dot { background:#484f58; }
.s-exited .status { color:#484f58; }
.s-exited { border-left-color:#484f58; }

@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
`;

export class SessionsWebviewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  private view: vscode.WebviewView | undefined;
  private refreshTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly disposables: vscode.Disposable[] = [];
  private terminalMapper: TerminalMapper | undefined;

  constructor(private readonly discovery: SessionDiscovery) {
    this.disposables.push(
      discovery.onDidChangeSession(() => this.refresh()),
    );
  }

  setTerminalMapper(mapper: TerminalMapper): void {
    this.terminalMapper = mapper;
  }

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;
    webviewView.webview.options = { enableScripts: true };
    webviewView.webview.onDidReceiveMessage(msg => {
      if (msg.type === 'focus' && typeof msg.sessionId === 'string') {
        void vscode.commands.executeCommand('claudeSessions.focusSession', msg.sessionId);
      }
    }, undefined, this.disposables);
    webviewView.onDidChangeVisibility(() => {
      if (webviewView.visible) this.updateHtml();
    }, undefined, this.disposables);
    this.updateHtml();
  }

  refresh(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = undefined;
      this.updateHtml();
    }, 500);
  }

  private getSortedSessions(): SessionInfo[] {
    const showExited = vscode.workspace.getConfiguration('claudeSessions').get<boolean>('showExited', false);
    const sessions = [...this.discovery.getSessions().values()];
    const filtered = sessions.filter(s => {
      if (!this.terminalMapper?.isOwnSessionSync(s.pid)) return false;
      if (!showExited && s.state === 'exited') return false;
      return true;
    });
    filtered.sort((a, b) => {
      const oa = stateSortOrder[a.state], ob = stateSortOrder[b.state];
      if (oa !== ob) return oa - ob;
      if (a.state === 'idle' && b.state === 'idle') return a.stateChangedAt - b.stateChangedAt;
      return 0;
    });
    return filtered;
  }

  private updateHtml(): void {
    if (!this.view) return;
    const webview = this.view.webview;
    const sessions = this.getSortedSessions();
    const nonce = getNonce();

    const rows = sessions.map(s => {
      const name = escapeHtml(s.slug ?? path.basename(s.cwd));
      const status = escapeHtml(getStatusText(s));
      return `<div class="row s-${s.state}" data-sid="${s.sessionId}">
  <div class="r1"><span class="dot"></span><span class="name">${name}</span></div>
  <div class="status">${status}</div>
</div>`;
    }).join('\n');

    const empty = sessions.length === 0
      ? '<div class="empty">No Claude Code sessions found.</div>'
      : '';

    webview.html = `<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
<style>${CSS}</style>
</head>
<body>
${empty}${rows}
<script nonce="${nonce}">
  const vscode = acquireVsCodeApi();
  document.addEventListener('click', function(e) {
    const row = e.target.closest('.row');
    if (row && row.dataset.sid) {
      vscode.postMessage({ type: 'focus', sessionId: row.dataset.sid });
    }
  });
</script>
</body></html>`;
  }

  dispose(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    for (const d of this.disposables) d.dispose();
  }
}
