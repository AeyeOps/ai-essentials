import * as vscode from 'vscode';
import * as path from 'node:path';
import type { SessionInfo, SessionState } from './types.js';
import type { SessionDiscovery } from './sessionDiscovery.js';
import type { TerminalMapper } from './terminalMapper.js';
import { formatDuration, getStatusText, getFilteredSortedSessions } from './sessionUtils.js';

const stateColorMap: Record<SessionState, string> = {
  idle: 'charts.green',
  thinking: 'charts.yellow',
  tool: 'charts.blue',
  prompt: 'editorWarning.foreground',
  permission: 'charts.red',
  error: 'charts.red',
  compact: 'charts.yellow',
  exited: 'disabledForeground',
};

export class SessionTreeItem extends vscode.TreeItem {
  constructor(public readonly session: SessionInfo, active: boolean) {
    const labelText = session.slug ?? path.basename(session.cwd);
    super(
      active ? { label: labelText, highlights: [[0, labelText.length]] } : labelText,
      vscode.TreeItemCollapsibleState.None,
    );
    this.description = getStatusText(session);
    this.iconPath = new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor(stateColorMap[session.state]));

    const elapsed = Date.now() - session.stateChangedAt;
    const tooltip = new vscode.MarkdownString();
    tooltip.appendMarkdown(`**State:** ${session.state}\n\n`);
    tooltip.appendMarkdown(`**Duration:** ${formatDuration(elapsed)}\n\n`);
    tooltip.appendMarkdown(`**CWD:** \`${session.cwd}\``);
    this.tooltip = tooltip;

    this.command = {
      command: 'aeoVscCcSessions.focusSession',
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
    const activeId = this.terminalMapper?.getActiveSessionId();
    return getFilteredSortedSessions(this.discovery, this.terminalMapper).map(
      s => new SessionTreeItem(s, s.sessionId === activeId),
    );
  }

  dispose(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    for (const d of this.disposables) d.dispose();
  }
}
