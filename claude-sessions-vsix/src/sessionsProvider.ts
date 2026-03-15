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

const stateColorMap: Record<SessionState, string> = {
  idle: 'charts.green',
  thinking: 'charts.yellow',
  tool: 'charts.blue',
  permission: 'charts.red',
  error: 'charts.red',
  compact: 'charts.yellow',
  exited: 'disabledForeground',
};

const stateSortOrder: Record<SessionState, number> = {
  tool: 0,
  thinking: 1,
  permission: 2,
  compact: 3,
  idle: 4,
  error: 5,
  exited: 6,
};

function getDescription(session: SessionInfo): string {
  const elapsed = Date.now() - session.stateChangedAt;
  switch (session.state) {
    case 'idle':
      return `Idle ${formatDuration(elapsed)}`;
    case 'thinking':
      return elapsed > 3000 ? `Thinking ${formatDuration(elapsed)}...` : 'Thinking...';
    case 'tool':
      if (session.toolName && session.toolDetail) return `${session.toolName}: ${session.toolDetail}`;
      return session.toolName ?? 'Tool';
    case 'permission':
      return 'Waiting for permission...';
    case 'compact':
      return 'Compacting context...';
    case 'error':
      return 'Error';
    case 'exited':
      return 'Exited';
  }
}

export class SessionTreeItem extends vscode.TreeItem {
  constructor(public readonly session: SessionInfo) {
    super(session.slug ?? path.basename(session.cwd), vscode.TreeItemCollapsibleState.None);
    this.description = getDescription(session);
    this.iconPath = new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor(stateColorMap[session.state]));

    const elapsed = Date.now() - session.stateChangedAt;
    const tooltip = new vscode.MarkdownString();
    tooltip.appendMarkdown(`**State:** ${session.state}\n\n`);
    tooltip.appendMarkdown(`**Duration:** ${formatDuration(elapsed)}\n\n`);
    tooltip.appendMarkdown(`**CWD:** \`${session.cwd}\``);
    this.tooltip = tooltip;

    this.command = {
      command: 'claudeSessions.focusSession',
      title: 'Focus Session',
      arguments: [session.sessionId],
    };
    this.contextValue = session.state;
  }
}

export class SessionsProvider implements vscode.TreeDataProvider<SessionTreeItem>, vscode.Disposable {
  private _onDidChangeTreeData = new vscode.EventEmitter<SessionTreeItem | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;
  private readonly disposables: vscode.Disposable[] = [];
  private refreshTimer: ReturnType<typeof setTimeout> | undefined;
  private terminalMapper: TerminalMapper | undefined;

  constructor(private readonly discovery: SessionDiscovery) {
    this.disposables.push(
      discovery.onDidChangeSession(() => this.refresh()),
      this._onDidChangeTreeData,
    );
  }

  setTerminalMapper(mapper: TerminalMapper): void {
    this.terminalMapper = mapper;
  }

  refresh(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = undefined;
      this._onDidChangeTreeData.fire();
    }, 500);
  }

  getTreeItem(element: SessionTreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: SessionTreeItem): SessionTreeItem[] {
    if (element) return [];

    const showExited = vscode.workspace.getConfiguration('claudeSessions').get<boolean>('showExited', false);
    const sessions = [...this.discovery.getSessions().values()];

    const filtered = sessions.filter(s => {
      if (!this.terminalMapper?.isOwnSessionSync(s.pid)) return false;
      if (!showExited && s.state === 'exited') return false;
      return true;
    });

    filtered.sort((a, b) => {
      const orderA = stateSortOrder[a.state];
      const orderB = stateSortOrder[b.state];
      if (orderA !== orderB) return orderA - orderB;
      if (a.state === 'idle' && b.state === 'idle') return a.stateChangedAt - b.stateChangedAt;
      return 0;
    });

    return filtered.map(s => new SessionTreeItem(s));
  }

  dispose(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    for (const d of this.disposables) d.dispose();
  }
}
