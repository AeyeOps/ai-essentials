import * as vscode from 'vscode';
import type { SessionDiscovery } from './sessionDiscovery.js';
import type { TerminalMapper } from './terminalMapper.js';
import {
  getFilteredSortedSessions,
  getRichSortedSessions,
  getSessionAgeText,
  getSessionDisplayName,
  getSessionShortId,
  getSubagentSummary,
  getStatusText,
  type RichSortMode,
} from './sessionUtils.js';

const README_URL = 'https://github.com/AeyeOps/ai-essentials/blob/main/aeo-cc-sessions-vsix/README.md';

function logFocusTrace(
  log: vscode.LogOutputChannel | undefined,
  traceId: string | undefined,
  stage: string,
  fields: Record<string, string | number | boolean | undefined>,
): void {
  if (!log) return;
  const payload = Object.entries(fields)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  log.info(`focus-trace trace=${JSON.stringify(traceId ?? null)} stage=${JSON.stringify(stage)}${payload ? ` ${payload}` : ''}`);
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function getNonce(): string {
  let text = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i += 1) {
    text += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return text;
}

function getUrgencyBadge(state: string): { cssClass: string; label: string } | undefined {
  switch (state) {
    case 'prompt':
      return { cssClass: 'input', label: 'Input' };
    case 'permission':
      return { cssClass: 'permission', label: 'Perm' };
    case 'error':
      return { cssClass: 'error', label: 'Error' };
    case 'tool':
      return { cssClass: 'tool', label: 'Tool' };
    default:
      return undefined;
  }
}

function areSetsEqual(a: Set<string>, b: Set<string>): boolean {
  if (a.size !== b.size) return false;
  for (const value of a) {
    if (!b.has(value)) return false;
  }
  return true;
}

function formatDiagnosticTimestamp(value: number | undefined): string {
  if (typeof value !== 'number' || Number.isNaN(value) || value <= 0) {
    return '—';
  }
  return new Date(value).toISOString();
}

function formatDiagnosticValue(value: unknown): string {
  if (value === undefined || value === null || value === '') {
    return '—';
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? String(value) : '—';
  }
  if (typeof value === 'string') {
    return value;
  }
  return JSON.stringify(value);
}

const CSS = `
*, *::before, *::after {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 0;
  background: var(--vscode-panel-background, var(--vscode-sideBar-background, #181818));
  color: var(--vscode-foreground, #d8d8d8);
  font: 13px/1.4 var(--vscode-font-family, system-ui);
}

.shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

.scroll-region {
  flex: 1;
  min-height: 0;
  overflow-x: hidden;
  overflow-y: auto;
  overflow-y: overlay;
}

.scroll-region::-webkit-scrollbar {
  width: 10px;
}

.scroll-region::-webkit-scrollbar-track {
  background: transparent;
}

.scroll-region::-webkit-scrollbar-thumb {
  background: rgba(255,255,255,0.16);
  border-radius: 999px;
}

.scroll-region:not(:hover)::-webkit-scrollbar-thumb {
  background: transparent;
}

.toolbar {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--vscode-panel-border, rgba(255,255,255,0.08));
  background: var(--vscode-panel-background, var(--vscode-sideBar-background, #181818));
}

.sort-button,
.help-button {
  height: 28px;
  border: 1px solid var(--vscode-button-secondaryBorder, rgba(255,255,255,0.12));
  background: var(--vscode-button-secondaryBackground, rgba(255,255,255,0.03));
  color: var(--vscode-button-secondaryForeground, var(--vscode-foreground, #ccc));
  padding: 0 10px;
  font: inherit;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  cursor: pointer;
}

.help-button:hover,
.sort-button:hover {
  background: var(--vscode-toolbar-hoverBackground, rgba(255,255,255,0.06));
}

.sort-button {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.sort-button .label {
  color: var(--vscode-descriptionForeground, #8d8d8d);
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.sort-button .value {
  color: inherit;
}

.list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.row {
  position: relative;
  width: 100%;
  border: 0;
  border-left: 3px solid transparent;
  border-bottom: 1px solid var(--vscode-panel-border, rgba(255,255,255,0.08));
  background: transparent;
  color: inherit;
  text-align: left;
  padding: 10px 12px 11px 23px;
  display: grid;
  gap: 5px;
  cursor: pointer;
  font: inherit;
  margin: 0;
}

.row.is-expanded {
  padding-bottom: 13px;
}

.row::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: 0;
}

.row:hover {
  background: var(--vscode-list-hoverBackground, rgba(255,255,255,0.04));
}

.row.is-visible {
  background: color-mix(in srgb, var(--vscode-terminal-ansiGreen, #3fb950) 11%, transparent);
}

.row.is-selected {
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--vscode-terminal-ansiBlue, #58a6ff) 19%, transparent),
    transparent 72%
  );
}

.row.s-prompt::after {
  background: linear-gradient(
    90deg,
    color-mix(in srgb, #f7f1e3 18%, transparent),
    transparent 78%
  );
  animation: attentionFlash 1.6s ease-in-out infinite;
}

.row.s-permission::after {
  background: linear-gradient(
    90deg,
    color-mix(in srgb, #f85149 16%, transparent),
    transparent 78%
  );
  animation: attentionFlash 1.2s ease-in-out infinite;
}

.row.is-selected.s-prompt::after {
  background: linear-gradient(
    90deg,
    color-mix(in srgb, #f7f1e3 14%, transparent),
    transparent 78%
  );
}

.row.is-selected.s-permission::after {
  background: linear-gradient(
    90deg,
    color-mix(in srgb, #f85149 13%, transparent),
    transparent 78%
  );
}

.row:last-child {
  border-bottom: 0;
}

.row.s-idle { border-left-color: var(--vscode-terminal-ansiGreen, #3fb950); }
.row.s-starting { border-left-color: #8b949e; }
.row.s-thinking { border-left-color: #d29922; }
.row.s-tool { border-left-color: var(--vscode-terminal-ansiBlue, #58a6ff); }
.row.s-prompt { border-left-color: #f7f1e3; }
.row.s-permission { border-left-color: #f85149; }
.row.s-error { border-left-color: #f85149; }
.row.s-compact { border-left-color: #d29922; }
.row.s-exited { border-left-color: #484f58; }

.row-top {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 12px;
  min-width: 0;
}

.title-block {
  display: flex;
  align-items: center;
  gap: 9px;
  min-width: 0;
}

.expander {
  flex: 0 0 auto;
  border: 0;
  background: transparent;
  color: var(--vscode-descriptionForeground, #8d8d8d);
  padding: 0;
  min-width: 22px;
  font: 12px/1 var(--vscode-editor-font-family, ui-monospace, monospace);
  cursor: pointer;
}

.expander:hover {
  color: var(--vscode-foreground, #d8d8d8);
}

.title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 15px;
  line-height: 1.02;
  font-weight: 700;
  letter-spacing: -0.02em;
}

.badge {
  display: inline-flex;
  align-items: center;
  border: 1px solid currentColor;
  padding: 4px 8px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  white-space: nowrap;
  max-width: 100%;
  overflow: hidden;
}

.badge.input { color: #efe1a2; }
.badge.permission { color: #ef7e68; }
.badge.error { color: #ef7e68; }
.badge.tool { color: var(--vscode-terminal-ansiBlue, #58a6ff); }

.path {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: #9da7a1;
  font: 11px/1.05 var(--vscode-editor-font-family, ui-monospace, monospace);
}

.path-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.path-trailing {
  color: var(--vscode-descriptionForeground, #8d8d8d);
  font-size: 11px;
  line-height: 1.05;
  white-space: nowrap;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.meta {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: var(--vscode-descriptionForeground, #8d8d8d);
  font-size: 11px;
  line-height: 1.02;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.meta .sep {
  color: #666;
  margin: 0 7px;
}

.diag {
  display: grid;
  gap: 4px;
  margin-top: 5px;
}

.diag-row {
  display: grid;
  grid-template-columns: 160px minmax(0, 1fr);
  gap: 10px;
  align-items: start;
  min-width: 0;
}

.diag-label {
  color: var(--vscode-descriptionForeground, #8d8d8d);
  font-size: 11px;
  line-height: 1.15;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.diag-value {
  color: var(--vscode-foreground, #d7ddd9);
  font: 11px/1.2 var(--vscode-editor-font-family, ui-monospace, monospace);
  white-space: normal;
  overflow-wrap: anywhere;
  word-break: break-word;
}

.activity {
  min-height: 1.1em;
  overflow: visible;
  white-space: normal;
  overflow-wrap: anywhere;
  word-break: break-word;
  color: var(--vscode-foreground, #d7ddd9);
  font-size: 12px;
  line-height: 1.06;
}

.row.is-selected .activity {
  color: color-mix(in srgb, var(--vscode-terminal-ansiGreen, #3fb950) 72%, white);
}

.empty {
  padding: 16px 12px;
  color: var(--vscode-descriptionForeground, #888);
}

.menu {
  position: fixed;
  z-index: 1000;
  min-width: 170px;
  padding: 6px 0;
  border: 1px solid var(--vscode-menu-border, rgba(255,255,255,0.12));
  background: var(--vscode-menu-background, #252526);
  box-shadow: 0 8px 24px rgba(0,0,0,0.35);
  display: none;
}

.menu.visible { display: block; }

.context-menu[data-mode="session"] [data-menu="background"],
.context-menu[data-mode="background"] [data-menu="session"] { display: none; }

.menu button {
  width: 100%;
  border: 0;
  background: transparent;
  color: var(--vscode-menu-foreground, var(--vscode-foreground, #ccc));
  text-align: left;
  padding: 7px 12px;
  font: inherit;
  cursor: pointer;
}

.menu button:hover,
.menu button.is-selected {
  background: var(--vscode-menu-selectionBackground, var(--vscode-list-hoverBackground, #2a2d30));
  color: var(--vscode-menu-selectionForeground, var(--vscode-foreground, #fff));
}

.menu hr {
  border: 0;
  border-top: 1px solid var(--vscode-menu-separatorBackground, rgba(255,255,255,0.12));
  margin: 4px 0;
}

@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
@keyframes attentionFlash { 0%,100%{opacity:0.15} 50%{opacity:0.55} }
`;

export class SessionsWebviewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  private view: vscode.WebviewView | undefined;
  private refreshTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly disposables: vscode.Disposable[] = [];
  private terminalMapper: TerminalMapper | undefined;
  private menuOpen = false;
  private refreshQueued = false;
  private selectedSessionId: string | undefined;
  private sortMode: RichSortMode = 'none';
  private optimisticVisibleIds: Set<string> | undefined;
  private optimisticVisibleUntil = 0;
  private expandedSessionIds = new Set<string>();

  constructor(
    private readonly discovery: SessionDiscovery,
    private readonly log?: vscode.LogOutputChannel,
  ) {
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
      if (msg.type === 'focus' && typeof msg.processKey === 'string') {
        const receivedAt = Date.now();
        const traceId = typeof msg.traceId === 'string' ? msg.traceId : undefined;
        logFocusTrace(this.log, traceId, 'webview.pointerdown.observed', {
          processKey: msg.processKey,
          pointerDownToReceiveMs: typeof msg.pointerDownAt === 'number' ? receivedAt - msg.pointerDownAt : undefined,
        });
        logFocusTrace(this.log, traceId, 'webview.click.observed', {
          processKey: msg.processKey,
          clickToReceiveMs: typeof msg.clickAt === 'number' ? receivedAt - msg.clickAt : undefined,
          clickDetail: typeof msg.clickDetail === 'number' ? msg.clickDetail : undefined,
        });
        this.selectedSessionId = msg.processKey;
        const optimisticGroup = this.terminalMapper?.getSessionGroupIds(msg.processKey);
        this.optimisticVisibleIds = optimisticGroup && optimisticGroup.size > 0
          ? optimisticGroup
          : new Set([msg.processKey]);
        this.optimisticVisibleUntil = Date.now() + 2000;
        logFocusTrace(this.log, traceId, 'webview.focus.dispatch', {
          processKey: msg.processKey,
          optimisticGroupSize: this.optimisticVisibleIds.size,
        });
        void (async () => {
          try {
            await vscode.commands.executeCommand('aeoVscCcSessions.focusSession', {
              processKey: msg.processKey,
              traceId,
              pointerDownAt: typeof msg.pointerDownAt === 'number' ? msg.pointerDownAt : undefined,
              clickAt: typeof msg.clickAt === 'number' ? msg.clickAt : undefined,
              webviewReceivedAt: receivedAt,
            });
            logFocusTrace(this.log, traceId, 'webview.focus.executeCommand-return', {
              processKey: msg.processKey,
              totalMsFromReceive: Date.now() - receivedAt,
            });
          } catch (error) {
            logFocusTrace(this.log, traceId, 'webview.focus.executeCommand-error', {
              processKey: msg.processKey,
              totalMsFromReceive: Date.now() - receivedAt,
              error: error instanceof Error ? error.message : String(error),
            });
          }
        })();
        this.updateHtml();
      } else if (msg.type === 'select' && typeof msg.processKey === 'string') {
        this.selectedSessionId = msg.processKey;
        this.updateHtml();
      } else if (msg.type === 'toggleExpanded' && typeof msg.processKey === 'string') {
        if (this.expandedSessionIds.has(msg.processKey)) {
          this.expandedSessionIds.delete(msg.processKey);
        } else {
          this.expandedSessionIds.add(msg.processKey);
        }
        this.updateHtml();
      } else if (msg.type === 'setSortMode' && typeof msg.sortMode === 'string') {
        if (msg.sortMode === 'none' || msg.sortMode === 'name' || msg.sortMode === 'state') {
          this.sortMode = msg.sortMode;
          this.updateHtml();
        }
      } else if (msg.type === 'openHelp') {
        void vscode.env.openExternal(vscode.Uri.parse(README_URL));
      } else if (msg.type === 'sessionAction' && typeof msg.processKey === 'string' && typeof msg.action === 'string') {
        this.selectedSessionId = msg.processKey;
        const command = msg.action === 'info'
          ? 'aeoVscCcSessions.sessionInfo'
          : msg.action === 'fork'
            ? 'aeoVscCcSessions.forkSession'
            : msg.action === 'close'
              ? 'aeoVscCcSessions.closeSession'
              : msg.action === 'rename'
                ? 'aeoVscCcSessions.renameSessionEntry'
              : msg.action === 'copy'
                ? 'aeoVscCcSessions.copySession'
                : undefined;
        if (command) {
          void vscode.commands.executeCommand(command, msg.processKey);
        }
        this.updateHtml();
      } else if (msg.type === 'viewAction' && typeof msg.action === 'string') {
        const command = msg.action === 'newSession'
          ? 'aeoVscCcSessions.newSession'
          : undefined;
        if (command) {
          void vscode.commands.executeCommand(command);
        }
      } else if (msg.type === 'menuState' && typeof msg.open === 'boolean') {
        this.menuOpen = msg.open;
        if (!this.menuOpen && this.refreshQueued) {
          this.refreshQueued = false;
          this.updateHtml();
        }
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
      if (this.menuOpen) {
        this.refreshQueued = true;
        return;
      }
      this.updateHtml();
    }, 500);
  }

  refreshNow(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = undefined;
    }
    if (this.menuOpen) {
      this.refreshQueued = true;
      return;
    }
    this.updateHtml();
  }

  clearOptimisticVisibleIds(): void {
    this.optimisticVisibleIds = undefined;
    this.optimisticVisibleUntil = 0;
  }

  private updateHtml(): void {
    if (!this.view) return;
    if (this.menuOpen) {
      this.refreshQueued = true;
      return;
    }

    const webview = this.view.webview;
    const actualActiveIds = this.terminalMapper?.getActiveSessionIds() ?? new Set<string>();
    if (
      this.optimisticVisibleIds
      && (
        Date.now() > this.optimisticVisibleUntil
        || areSetsEqual(actualActiveIds, this.optimisticVisibleIds)
      )
    ) {
      this.clearOptimisticVisibleIds();
    }
    const activeIds = this.optimisticVisibleIds ?? actualActiveIds;
    const sessions = getRichSortedSessions(
      getFilteredSortedSessions(this.discovery, this.terminalMapper),
      this.sortMode,
    );

    if (this.selectedSessionId && !sessions.some(session => session.processKey === this.selectedSessionId)) {
      this.selectedSessionId = activeIds.size === 1 ? [...activeIds][0] : undefined;
    } else if (!this.selectedSessionId && activeIds.size === 1) {
      this.selectedSessionId = [...activeIds][0];
    }
    const sessionIds = new Set(sessions.map(session => session.processKey));
    this.expandedSessionIds = new Set(
      [...this.expandedSessionIds].filter(processKey => sessionIds.has(processKey)),
    );

    const nonce = getNonce();
    const buildDiagnosticRows = (session: typeof sessions[number]): string => {
      const fields: Array<[string, string]> = [
        ['Process Key', formatDiagnosticValue(session.processKey)],
        ['PID', formatDiagnosticValue(session.pid)],
        ['PID Start Ticks', formatDiagnosticValue(session.pidStartTicks)],
        ['Current Session ID', formatDiagnosticValue(session.sessionId)],
        ['Registry Session ID', formatDiagnosticValue(session.registrySessionId)],
        ['Transcript Session ID', formatDiagnosticValue(session.transcriptSessionId)],
        ['Transcript Path', formatDiagnosticValue(session.transcriptPath)],
        ['CWD', formatDiagnosticValue(session.cwd)],
        ['State', formatDiagnosticValue(session.state)],
        ['Tool Name', formatDiagnosticValue(session.toolName)],
        ['Tool Detail', formatDiagnosticValue(session.toolDetail)],
        ['Active Subagent Count', formatDiagnosticValue(session.activeSubagentCount)],
        ['Sidecar Health', formatDiagnosticValue(session.sidecarHealth)],
        ['Sidecar Message', formatDiagnosticValue(session.sidecarMessage)],
        ['Start Source', formatDiagnosticValue(session.startSource)],
        ['Previous Session ID', formatDiagnosticValue(session.previousTranscriptSessionId)],
        ['Previous Transcript Path', formatDiagnosticValue(session.previousTranscriptPath)],
        ['Custom Title', formatDiagnosticValue(session.customTitle)],
        ['Agent Name', formatDiagnosticValue(session.agentName)],
        ['Slug', formatDiagnosticValue(session.slug)],
        ['Registry Slug', formatDiagnosticValue(session.registrySlug)],
        ['Started At', formatDiagnosticTimestamp(session.startedAt)],
        ['Observed At', formatDiagnosticTimestamp(session.observedAt)],
        ['State Changed At', formatDiagnosticTimestamp(session.stateChangedAt)],
        ['Sidecar Updated At', formatDiagnosticTimestamp(session.sidecarUpdatedAt)],
        ['Terminal Name', formatDiagnosticValue(session.terminal?.name)],
        ['Visible In Active Terminal', formatDiagnosticValue(activeIds.has(session.processKey))],
      ];
      return `<div class="diag">${fields.map(([label, value]) => (
        `<div class="diag-row"><div class="diag-label">${escapeHtml(label)}</div><div class="diag-value">${escapeHtml(value)}</div></div>`
      )).join('')}</div>`;
    };
    const rows = sessions.map(session => {
      const badge = getUrgencyBadge(session.state);
      const visible = activeIds.has(session.processKey) ? ' is-visible' : '';
      const selected = session.processKey === this.selectedSessionId ? ' is-selected' : '';
      const expanded = this.expandedSessionIds.has(session.processKey) ? ' is-expanded' : '';
      const title = escapeHtml(getSessionDisplayName(session));
      const fullPath = escapeHtml(session.cwd);
      const shortId = escapeHtml(getSessionShortId(session));
      const age = escapeHtml(getSessionAgeText(session));
      const subagentSummary = session.state === 'idle'
        ? undefined
        : getSubagentSummary(session.activeSubagentCount);
      const activity = escapeHtml(getStatusText(session));
      const badgeHtml = badge
        ? `<span class="badge ${badge.cssClass}">${escapeHtml(badge.label)}</span>`
        : '';
      const metaParts = [`sid ${shortId}`];
      if (subagentSummary) {
        metaParts.push(escapeHtml(subagentSummary));
      }
      metaParts.push(age);
      const metaHtml = metaParts.join('<span class="sep">•</span>');
      const expanderLabel = this.expandedSessionIds.has(session.processKey) ? '[-]' : '[+]';
      const diagnosticHtml = this.expandedSessionIds.has(session.processKey)
        ? buildDiagnosticRows(session)
        : '';

      return `<div class="row s-${session.state}${visible}${selected}${expanded}" data-sid="${session.processKey}" title="${fullPath}">
  <div class="row-top">
    <div class="title-block"><button class="expander" data-row-action="toggle-expanded" data-process-key="${session.processKey}" aria-expanded="${this.expandedSessionIds.has(session.processKey)}" type="button">${expanderLabel}</button><span class="title">${title}</span></div>
    ${badgeHtml}
  </div>
  <div class="path-row"><div class="path" data-full-path="${fullPath}"></div></div>
  <div class="meta">${metaHtml}</div>
  ${diagnosticHtml}
  <div class="activity">${activity}</div>
</div>`;
    }).join('\n');

    const empty = sessions.length === 0
      ? '<div class="empty">No Claude Code sessions found.</div>'
      : '';

    const sortLabel = this.sortMode === 'name'
      ? 'Name'
      : this.sortMode === 'state'
        ? 'State'
        : 'None';
    const sortMenuButton = (mode: RichSortMode, label: string): string => (
      `<button data-sort-mode="${mode}" class="${this.sortMode === mode ? 'is-selected' : ''}" type="button">${label}</button>`
    );
    webview.html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
  <style>${CSS}</style>
</head>
<body>
  <div class="shell">
    <div class="toolbar">
      <button id="sortButton" class="sort-button" type="button"><span class="label">Sort</span><span class="value">${sortLabel}</span></button>
      <button id="helpButton" class="help-button" type="button">Help</button>
    </div>
    <div class="scroll-region">
      <div class="list">
        ${empty}${rows}
      </div>
    </div>
  </div>
  <div id="sortMenu" class="menu" role="menu" aria-label="Sort sessions">
    ${sortMenuButton('none', 'None')}
    ${sortMenuButton('name', 'Name')}
    ${sortMenuButton('state', 'State')}
  </div>
  <div id="contextMenu" class="menu context-menu" role="menu" aria-label="Session actions">
    <button data-action="info" data-menu="session" type="button">Info</button>
    <button data-action="fork" data-menu="session" type="button">Fork Session</button>
    <button data-action="close" data-menu="session" type="button">Close Session</button>
    <button data-action="rename" data-menu="session" type="button">Rename</button>
    <hr data-menu="session" />
    <button data-action="copy" data-menu="session" type="button">Copy</button>
    <button data-action="newSession" data-menu="background" type="button">New Session</button>
  </div>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const sortButton = document.getElementById('sortButton');
    const sortMenu = document.getElementById('sortMenu');
    const contextMenu = document.getElementById('contextMenu');
    const helpButton = document.getElementById('helpButton');
    let contextSessionId = undefined;
    let contextMenuMode = undefined;
    let sortMenuOpen = false;
    let pathMeasureContext = undefined;
    let nextFocusTraceCounter = 1;
    let lastPointerDown = undefined;

    function findClosestElement(target, selector) {
      return target instanceof Element ? target.closest(selector) : null;
    }

    function publishMenuState(open) {
      vscode.postMessage({ type: 'menuState', open });
    }

    function closeSortMenu() {
      sortMenu.classList.remove('visible');
      sortMenu.style.visibility = '';
      sortMenuOpen = false;
    }

    function openSortMenu() {
      const rect = sortButton.getBoundingClientRect();
      sortMenu.classList.add('visible');
      sortMenu.style.left = '0px';
      sortMenu.style.top = '0px';
      sortMenu.style.visibility = 'hidden';

      const menuWidth = sortMenu.offsetWidth;
      const menuHeight = sortMenu.offsetHeight;
      const maxLeft = Math.max(4, window.innerWidth - menuWidth - 4);
      const maxTop = Math.max(4, window.innerHeight - menuHeight - 4);
      const clampedLeft = Math.min(Math.max(4, rect.right - menuWidth), maxLeft);
      const clampedTop = Math.min(Math.max(4, rect.bottom + 4), maxTop);
      sortMenu.style.left = clampedLeft + 'px';
      sortMenu.style.top = clampedTop + 'px';
      sortMenu.style.visibility = 'visible';
      sortMenuOpen = true;
    }

    function hideContextMenu() {
      if (!contextMenu.classList.contains('visible')) {
        contextSessionId = undefined;
        contextMenuMode = undefined;
        return;
      }
      contextMenu.classList.remove('visible');
      contextMenu.style.visibility = '';
      contextSessionId = undefined;
      contextMenuMode = undefined;
      publishMenuState(false);
    }

    function showContextMenu(mode, x, y, sessionId) {
      contextMenuMode = mode;
      contextSessionId = sessionId;
      contextMenu.dataset.mode = mode;
      contextMenu.classList.add('visible');
      contextMenu.style.left = '0px';
      contextMenu.style.top = '0px';
      contextMenu.style.visibility = 'hidden';

      const menuWidth = contextMenu.offsetWidth;
      const menuHeight = contextMenu.offsetHeight;
      const maxLeft = Math.max(4, window.innerWidth - menuWidth - 4);
      const maxTop = Math.max(4, window.innerHeight - menuHeight - 4);
      const clampedLeft = Math.min(Math.max(4, x), maxLeft);
      const clampedTop = Math.min(Math.max(4, y), maxTop);

      contextMenu.style.left = clampedLeft + 'px';
      contextMenu.style.top = clampedTop + 'px';
      contextMenu.style.visibility = 'visible';
      publishMenuState(true);
    }

    function getPathMeasureContext(referenceElement) {
      if (!pathMeasureContext) {
        const canvas = document.createElement('canvas');
        pathMeasureContext = canvas.getContext('2d');
      }
      const styles = window.getComputedStyle(referenceElement);
      pathMeasureContext.font = \`\${styles.fontWeight} \${styles.fontSize} \${styles.fontFamily}\`;
      return pathMeasureContext;
    }

    function abbreviateSegment(segment) {
      if (!segment) return '';
      if (segment.length <= 4) return segment;

      const isHidden = segment.startsWith('.');
      const raw = isHidden ? segment.slice(1) : segment;
      const parts = raw.split(/[-_]/).filter(Boolean);
      let compact = '';

      if (parts.length > 1) {
        compact = parts.slice(0, 3).map(part => part.slice(0, 1)).join('-');
      } else {
        compact = raw.slice(0, isHidden ? 2 : 1);
      }

      return isHidden ? \`.\${compact}\` : compact;
    }

    function compactPathSegments(fullPath) {
      if (!fullPath) return fullPath;

      const absolute = fullPath.startsWith('/');
      const parts = fullPath.split('/').filter(Boolean);
      if (parts.length === 0) return fullPath;

      const display = [...parts];
      const prefix = absolute ? '/' : '';
      const middleStart = 1;
      const middleEnd = Math.max(parts.length - 2, middleStart);
      for (let i = middleStart; i < middleEnd; i += 1) {
        display[i] = abbreviateSegment(display[i]);
      }

      if (display.length > 0) {
        display[0] = abbreviateSegment(display[0]);
      }

      if (display.length > 2) {
        display[display.length - 2] = abbreviateSegment(display[display.length - 2]);
      }

      return { absolute, parts, display, prefix };
    }

    function compactPathToWidth(fullPath, referenceElement) {
      if (!referenceElement) return fullPath;

      const context = getPathMeasureContext(referenceElement);
      const maxWidth = Math.max(20, referenceElement.clientWidth - 2);
      if (context.measureText(fullPath).width <= maxWidth) return fullPath;

      const shape = compactPathSegments(fullPath);
      if (!shape || typeof shape === 'string') return fullPath;

      const { parts, display, prefix } = shape;
      let candidate = prefix + display.join('/');
      if (context.measureText(candidate).width <= maxWidth) return candidate;

      if (parts.length > 1) {
        candidate = \`\${prefix}\${display[0]}/…/\${parts.at(-1)}\`;
        if (context.measureText(candidate).width <= maxWidth) return candidate;

        const tail = [];
        for (let i = parts.length - 1; i >= 1; i -= 1) {
          tail.unshift(parts[i]);
          const nextCandidate = \`\${prefix}…/\${tail.join('/')}\`;
          if (context.measureText(nextCandidate).width > maxWidth) {
            tail.shift();
            break;
          }
          candidate = nextCandidate;
        }
        return candidate;
      }

      return fullPath;
    }

    function updatePathLabels() {
      document.querySelectorAll('.path').forEach(element => {
        const fullPath = element.dataset.fullPath || '';
        element.textContent = compactPathToWidth(fullPath, element);
      });
    }

    sortButton.addEventListener('click', event => {
      event.stopPropagation();
      if (sortMenuOpen) {
        closeSortMenu();
        return;
      }
      hideContextMenu();
      openSortMenu();
    });

    helpButton.addEventListener('click', () => {
      vscode.postMessage({ type: 'openHelp' });
    });

    document.addEventListener('pointerdown', event => {
      if (event.button === 2) {
        return;
      }
      if (findClosestElement(event.target, '[data-row-action]')) {
        lastPointerDown = undefined;
        return;
      }
      const row = findClosestElement(event.target, '.row');
      if (!row || !row.dataset.sid) {
        lastPointerDown = undefined;
        return;
      }
      lastPointerDown = {
        processKey: row.dataset.sid,
        at: Date.now(),
        button: event.button,
      };
    });

    document.addEventListener('click', e => {
      if (e.button !== 0) {
        return;
      }
      if (sortMenu.contains(e.target)) {
        const button = findClosestElement(e.target, 'button[data-sort-mode]');
        if (button) {
          vscode.postMessage({ type: 'setSortMode', sortMode: button.dataset.sortMode });
        }
        closeSortMenu();
        hideContextMenu();
        return;
      }

      if (contextMenu.contains(e.target)) {
        const button = findClosestElement(e.target, 'button[data-action]');
        if (button) {
          if (contextMenuMode === 'session' && contextSessionId) {
            vscode.postMessage({ type: 'sessionAction', action: button.dataset.action, processKey: contextSessionId });
          } else if (contextMenuMode === 'background') {
            vscode.postMessage({ type: 'viewAction', action: button.dataset.action });
          }
        }
        hideContextMenu();
        return;
      }

      const rowAction = findClosestElement(e.target, '[data-row-action]');
      if (rowAction && rowAction.dataset.rowAction === 'toggle-expanded' && rowAction.dataset.processKey) {
        vscode.postMessage({ type: 'toggleExpanded', processKey: rowAction.dataset.processKey });
        closeSortMenu();
        hideContextMenu();
        return;
      }

      const row = findClosestElement(e.target, '.row');
      if (row && row.dataset.sid) {
        const clickAt = Date.now();
        const pointerDownAt = lastPointerDown && lastPointerDown.processKey === row.dataset.sid
          ? lastPointerDown.at
          : undefined;
        const traceId = \`\${clickAt}-\${nextFocusTraceCounter}-\${row.dataset.sid}\`;
        nextFocusTraceCounter += 1;
        vscode.postMessage({
          type: 'focus',
          processKey: row.dataset.sid,
          traceId,
          pointerDownAt,
          clickAt,
          clickDetail: e.detail,
        });
      }
      closeSortMenu();
      hideContextMenu();
    });

    document.addEventListener('contextmenu', e => {
      e.stopPropagation();
      closeSortMenu();
      if (contextMenu.contains(e.target)) {
        e.preventDefault();
        return;
      }

      const row = findClosestElement(e.target, '.row');
      e.preventDefault();
      if (row && row.dataset.sid) {
        showContextMenu('session', e.clientX, e.clientY, row.dataset.sid);
        return;
      }
      showContextMenu('background', e.clientX, e.clientY, undefined);
    });

    const pathResizeObserver = new ResizeObserver(() => updatePathLabels());
    pathResizeObserver.observe(document.body);
    window.addEventListener('blur', () => {
      closeSortMenu();
      hideContextMenu();
    });
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape') {
        closeSortMenu();
        hideContextMenu();
      }
    });
    requestAnimationFrame(() => updatePathLabels());
  </script>
</body>
</html>`;
  }

  dispose(): void {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    for (const d of this.disposables) d.dispose();
  }
}
