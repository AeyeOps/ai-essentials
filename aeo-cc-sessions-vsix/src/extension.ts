import * as path from 'node:path';
import * as vscode from 'vscode';
import {
  SessionDiscovery,
  resolveContinueFromCmdline,
  resolveConversationFromCmdline,
  resolveTaskFromFd,
} from './sessionDiscovery.js';
import { StateDetector } from './stateDetector.js';
import { SessionsWebviewProvider } from './sessionsWebviewProvider.js';
import { TerminalMapper } from './terminalMapper.js';
import { detectPlatform } from './platform.js';
import { TranscriptResolver } from './transcriptResolver.js';
import type { SessionInfo, SessionState } from './types.js';
import { readCmdlineArgs, readProcChain } from './proc.js';
import {
  applySidecarAssessment,
  assessSidecarForSession,
  installOrUpdateRuntime,
  listInstalledSidecarCandidates,
  loadInstalledSidecar,
  removeBundledSidecar,
  SIDECAR_MARKETPLACE_SOURCE,
} from './sidecarRuntime.js';
import { getSessionDisplayName } from './sessionUtils.js';

const RUNTIME_ISSUE_NOTIFY_DELAY_MS = 8000;
const TRANSCRIPT_PRESENTATION_REFRESH_TTL_MS = 10_000;
const INTERACTION_REFRESH_GRACE_MS = 4_000;

function createDetector(
  discovery: SessionDiscovery,
  providers: { refresh(): void },
  session: SessionInfo,
  transcriptResolver: TranscriptResolver,
  detectorPollInterval: number,
  loadResolvedTranscriptId: (sessionKey: string) => string | undefined,
  storeResolvedTranscriptId: (sessionKey: string, transcriptSessionId: string) => void,
  log: vscode.LogOutputChannel,
): StateDetector {
  let lastResolvedSessionId = session.transcriptSessionId
    ?? loadResolvedTranscriptId(session.processKey)
    ?? session.sessionId;
  let lastResolvedPath = session.transcriptPath;
  const resolve = () => {
    const target = transcriptResolver.resolve(
      session.pid,
      session.cwd,
      session.sessionId,
      lastResolvedSessionId,
      session.startedAt,
    );

    const changed = lastResolvedSessionId !== target.sessionId || lastResolvedPath !== target.path;
    lastResolvedSessionId = target.sessionId;
    lastResolvedPath = target.path;
    if (session.sidecarHealth !== 'healthy') {
      session.transcriptSessionId = target.sessionId;
      session.transcriptPath = target.path;
    }
    storeResolvedTranscriptId(session.processKey, target.sessionId);
    if (changed) {
      log.debug(
        `Resolved transcript: ${session.processKey} sid=${session.sessionId.slice(0, 8)} pid=${session.pid} -> ${target.sessionId.slice(0, 8)} (${target.source})`,
      );
      providers.refresh();
    }
    return target.path;
  };

  log.debug(`Creating detector: ${session.processKey} sid=${session.sessionId.slice(0, 8)} pid=${session.pid}`);
  const detector = new StateDetector(resolve, session.processKey, session.pid, detectorPollInterval, (_sid: string, state: SessionState, toolName?: string, toolDetail?: string) => {
    const s = discovery.getSession(_sid);
    if (s) {
      if (s.sidecarHealth !== 'healthy') {
        s.state = state;
        s.toolName = toolName;
        s.toolDetail = toolDetail;
        s.stateChangedAt = Date.now();
      }
      providers.refresh();
    }
  }, log);
  detector.start();
  return detector;
}

function sanitizeInstallFailureText(value: string): string {
  return value
    .replace(/aeo-vsc-cc-sessions-sidecar@aeo-skill-marketplace/g, 'Claude runtime')
    .replace(/aeo-vsc-cc-sessions-sidecar/g, 'Claude runtime')
    .replace(/aeo-skill-marketplace/g, 'the configured marketplace');
}

function describeInstallFailure(failed: { step: string; code: number; stdout: string; stderr: string }): {
  title: string;
  detail: string;
  actions: string[];
} {
  const stderr = sanitizeInstallFailureText(failed.stderr.trim());
  const stdout = sanitizeInstallFailureText(failed.stdout.trim());
  const combined = `${stderr}\n${stdout}`;

  if (failed.step === 'plugin_install' && /not found in marketplace/i.test(combined)) {
    return {
      title: 'We’re having trouble finding the plugin in the marketplace.',
      detail: [
        'The marketplace was reached, but the runtime plugin was not found in the marketplace contents.',
        '',
        'Try this:',
        '1. Open Marketplace and confirm the runtime plugin has been published.',
        '2. Retry Install after the marketplace has been updated.',
        '3. Follow the current Claude Code plugin and marketplace guidance if you want to install the marketplace and plugin manually.',
        '4. Use Open Logs if you want the technical details.',
      ].join('\n'),
      actions: ['Open Marketplace', 'Retry Install', 'Open Logs'],
    };
  }

  if (failed.step === 'marketplace_add') {
    return {
      title: 'Could not add the Claude marketplace.',
      detail: [
        'VS Code could not register the marketplace source needed to install the runtime plugin.',
        '',
        'Try this:',
        '1. Retry Install to try the marketplace add again.',
        '2. Open Marketplace to confirm the repository is reachable.',
        '3. Use Open Logs if you want the technical details.',
      ].join('\n'),
      actions: ['Retry Install', 'Open Marketplace', 'Open Logs'],
    };
  }

  if (failed.step === 'marketplace_update') {
    return {
      title: 'Could not refresh the Claude marketplace.',
      detail: [
        'VS Code added the marketplace, but Claude could not refresh its contents before plugin installation.',
        '',
        'Try this:',
        '1. Retry Install to fetch the latest marketplace contents again.',
        '2. Open Marketplace to confirm the repository is reachable.',
        '3. Use Open Logs if you want the technical details.',
      ].join('\n'),
      actions: ['Retry Install', 'Open Marketplace', 'Open Logs'],
    };
  }

  if (failed.step === 'plugin_enable') {
    return {
      title: 'Claude runtime was installed but could not be enabled.',
      detail: [
        'The install step completed, but Claude did not enable the runtime plugin.',
        '',
        'Try this:',
        '1. Retry Install to run the enable step again.',
        '2. Use Open Logs if you want the technical details.',
        '3. Open Marketplace to confirm the expected plugin is available there.',
      ].join('\n'),
      actions: ['Retry Install', 'Open Logs', 'Open Marketplace'],
    };
  }

  return {
    title: 'Claude runtime could not be installed.',
    detail: [
      'Try this:',
      '1. Retry Install.',
      '2. Use Open Logs if you want the technical details.',
      '3. Open Marketplace to confirm the source is reachable.',
    ].join('\n'),
    actions: ['Retry Install', 'Open Logs', 'Open Marketplace'],
  };
}

function resolveSessionTarget(
  discovery: SessionDiscovery,
  target: unknown,
): SessionInfo | undefined {
  if (typeof target === 'string') {
    return discovery.getSession(target);
  }
  if (target && typeof target === 'object') {
    const maybeTreeItem = target as { session?: SessionInfo };
    if (maybeTreeItem.session?.processKey) {
      return discovery.getSession(maybeTreeItem.session.processKey) ?? maybeTreeItem.session;
    }
    const maybeSession = target as SessionInfo;
    if (typeof maybeSession.processKey === 'string') {
      return discovery.getSession(maybeSession.processKey) ?? maybeSession;
    }
  }
  return undefined;
}

interface FocusSessionCommandArgs {
  processKey: string;
  traceId?: string;
  pointerDownAt?: number;
  clickAt?: number;
  webviewReceivedAt?: number;
}

interface PendingFocusRequest extends FocusSessionCommandArgs {
  requestedAt: number;
}

function resolveFocusSessionCommandArgs(target: unknown): FocusSessionCommandArgs | undefined {
  if (typeof target === 'string') {
    return { processKey: target };
  }
  if (!target || typeof target !== 'object') {
    return undefined;
  }

  const args = target as Partial<FocusSessionCommandArgs>;
  if (typeof args.processKey !== 'string') {
    return undefined;
  }

  return {
    processKey: args.processKey,
    traceId: typeof args.traceId === 'string' ? args.traceId : undefined,
    pointerDownAt: typeof args.pointerDownAt === 'number' ? args.pointerDownAt : undefined,
    clickAt: typeof args.clickAt === 'number' ? args.clickAt : undefined,
    webviewReceivedAt: typeof args.webviewReceivedAt === 'number' ? args.webviewReceivedAt : undefined,
  };
}

function logFocusTrace(
  log: vscode.LogOutputChannel,
  traceId: string | undefined,
  stage: string,
  fields: Record<string, string | number | boolean | undefined>,
): void {
  const payload = Object.entries(fields)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  log.info(`focus-trace trace=${JSON.stringify(traceId ?? null)} stage=${JSON.stringify(stage)}${payload ? ` ${payload}` : ''}`);
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_./:=+-]+$/u.test(value)) {
    return value;
  }
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

function normalizeClaudeLaunchArgs(cmdlineArgs: string[] | undefined): string[] {
  if (!cmdlineArgs || cmdlineArgs.length === 0) return [];

  const executable = path.basename(cmdlineArgs[0]).toLowerCase();
  let startIndex = 1;
  if (
    ['node', 'node.exe', 'bun', 'bun.exe'].includes(executable)
    && cmdlineArgs.length > 1
  ) {
    startIndex = 2;
  }

  const filtered: string[] = [];
  const args = cmdlineArgs.slice(startIndex);
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--resume') {
      index += 1;
      continue;
    }
    if (arg === '--continue' || arg === '--fork-session') {
      continue;
    }
    filtered.push(arg);
  }
  return filtered;
}

function resolveForkTargetSessionId(session: SessionInfo): string | undefined {
  return session.transcriptSessionId || session.sessionId;
}

interface ClaudeLaunchCommand {
  cwd: string;
  shellCommand: string;
  terminalCommand: string;
  claudeArgs: string[];
  terminalName: string;
}

function buildClaudeCommand(cwd: string, claudeArgs: string[], terminalName: string): ClaudeLaunchCommand {
  const quotedArgs = claudeArgs.map(shellQuote).join(' ');
  const terminalCommand = quotedArgs.length > 0 ? `claude ${quotedArgs}` : 'claude';
  const shellCommand = `cd ${shellQuote(cwd)} && ${terminalCommand}`;
  return {
    cwd,
    shellCommand,
    terminalCommand,
    claudeArgs,
    terminalName,
  };
}

function buildForkSessionCommand(session: SessionInfo): ClaudeLaunchCommand & { resumeSessionId: string } {
  const currentSessionId = resolveForkTargetSessionId(session);
  if (!currentSessionId) {
    throw new Error('Current session id is unavailable.');
  }

  const originalCmdlineArgs = readCmdlineArgs(session.pid);
  const preservedArgs = normalizeClaudeLaunchArgs(originalCmdlineArgs);
  const claudeArgs = [...preservedArgs, '--resume', currentSessionId, '--fork-session'];
  return {
    ...buildClaudeCommand(
      session.cwd,
      claudeArgs,
      `zsh ${session.slug ?? path.basename(session.cwd)}`,
    ),
    resumeSessionId: currentSessionId,
  };
}

function buildNewSessionCommand(): ClaudeLaunchCommand {
  const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
  if (!workspaceFolder) {
    throw new Error('New Session requires an open workspace folder.');
  }
  const cwd = workspaceFolder.uri.fsPath;
  const label = workspaceFolder.name || path.basename(cwd) || 'workspace';
  return buildClaudeCommand(cwd, ['--debug', '--verbose'], `zsh ${label}`);
}

function launchClaudeTerminal(command: ClaudeLaunchCommand): vscode.Terminal {
  const terminal = vscode.window.createTerminal({
    name: command.terminalName,
    cwd: command.cwd,
  });
  terminal.show(true);
  terminal.sendText(command.terminalCommand, true);
  return terminal;
}

function formatTimestamp(value: number | undefined): string {
  if (typeof value !== 'number' || Number.isNaN(value)) return 'unknown';
  return new Date(value).toISOString();
}

function summarizeCmdline(args: string[] | undefined): string {
  if (!args || args.length === 0) return '(unavailable)';
  return args.map(shellQuote).join(' ');
}

async function showSessionInfo(session: SessionInfo, transcriptResolver: TranscriptResolver): Promise<void> {
  const terminalPid = session.terminal ? await session.terminal.processId : undefined;
  const processChain = readProcChain(session.pid, terminalPid);
  const cmdlineArgs = readCmdlineArgs(session.pid);
  const forkCommand = buildForkSessionCommand(session);
  const title = getSessionDisplayName(session);
  const lineageStack = transcriptResolver.getLineageStack(
    session.cwd,
    session.transcriptSessionId ?? session.sessionId,
    session.transcriptPath,
  );
  const lineageRows = lineageStack.map((item, index) => `
    <div class="row">
      <div class="label">${index === 0 ? 'Current' : `Ancestor ${index}`}</div>
      <div class="meta">session=${escapeHtml(item.sessionId)} link=${escapeHtml(item.linkSource)}${item.startKind ? ` start=${escapeHtml(item.startKind)}` : ''}</div>
      <div class="detail">${escapeHtml(item.path ?? '(path unavailable)')}</div>
    </div>
  `).join('');
  const processRows = processChain.map(info => `
    <div class="row">
      <div class="label">PID ${info.pid}</div>
      <div class="meta">ppid=${info.ppid} startTicks=${info.startTicks} tty=${escapeHtml(info.tty ?? 'unknown')}</div>
      <div class="detail">${escapeHtml(summarizeCmdline(info.cmdlineArgs))}</div>
    </div>
  `).join('');

  const html = `<!DOCTYPE html>
  <html>
    <head>
      <meta charset="UTF-8" />
      <style>
        :root {
          color-scheme: dark;
        }
        body {
          margin: 0;
          padding: 14px 16px 12px;
          font-family: var(--vscode-font-family, system-ui);
          font-size: 13px;
          color: var(--vscode-foreground);
          background: var(--vscode-editorHoverWidget-background, var(--vscode-editorWidget-background, #252526));
          border-top: 1px solid var(--vscode-editorHoverWidget-border, rgba(255,255,255,0.14));
        }
        h1 {
          margin: 0 0 12px;
          font-size: 15px;
          font-weight: 600;
        }
        h2 {
          margin: 14px 0 6px;
          font-size: 12px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: var(--vscode-descriptionForeground);
        }
        .row {
          margin: 0 0 10px;
          padding-bottom: 10px;
          border-bottom: 1px solid rgba(255,255,255,0.08);
        }
        .row:last-child {
          border-bottom: 0;
          padding-bottom: 0;
        }
        .label {
          font-weight: 600;
          margin-bottom: 2px;
        }
        .meta {
          color: var(--vscode-descriptionForeground);
          margin-bottom: 4px;
          white-space: pre-wrap;
          word-break: break-word;
        }
        .detail, code {
          font-family: var(--vscode-editor-font-family, ui-monospace, monospace);
          font-size: 12px;
          white-space: pre-wrap;
          word-break: break-word;
        }
        code {
          background: rgba(255,255,255,0.06);
          padding: 1px 4px;
          border-radius: 4px;
        }
      </style>
    </head>
    <body>
      <h1>${escapeHtml(title)}</h1>

      <h2>Session</h2>
      <div class="row">
        <div class="label">Session ID</div>
        <div class="detail">${escapeHtml(session.sessionId)}</div>
        <div class="meta">processKey=${escapeHtml(session.processKey)} cwd=${escapeHtml(session.cwd)}</div>
      </div>
      <div class="row">
        <div class="label">State</div>
        <div class="meta">state=${escapeHtml(session.state)} runtime=${escapeHtml(session.sidecarHealth ?? 'unknown')}</div>
        <div class="detail">${escapeHtml(session.sidecarMessage ?? `observedAt=${formatTimestamp(session.observedAt)}`)}</div>
      </div>
      <div class="row">
        <div class="label">Transcript</div>
        <div class="meta">${escapeHtml(session.transcriptSessionId ?? 'unknown')}</div>
        <div class="detail">${escapeHtml(session.transcriptPath ?? '(unavailable)')}</div>
      </div>

      <h2>Lineage</h2>
      <div class="row">
        <div class="label">Start Source</div>
        <div class="detail">${escapeHtml(session.startSource ?? 'unknown')}</div>
        <div class="meta">previousSession=${escapeHtml(session.previousTranscriptSessionId ?? 'none')}</div>
        <div class="detail">${escapeHtml(session.previousTranscriptPath ?? 'none')}</div>
      </div>
      ${lineageRows ? `<h2>Lineage Stack</h2>${lineageRows}` : ''}

      <h2>Launch</h2>
      <div class="row">
        <div class="label">Fork Command</div>
        <div class="detail">${escapeHtml(forkCommand.shellCommand)}</div>
      </div>
      <div class="row">
        <div class="label">Current Claude Command</div>
        <div class="detail">${escapeHtml(summarizeCmdline(cmdlineArgs))}</div>
      </div>
      <div class="row">
        <div class="label">Resume Target</div>
        <div class="meta">resume=${escapeHtml(resolveConversationFromCmdline(session.pid) ?? 'none')} continue=${escapeHtml(String(resolveContinueFromCmdline(session.pid)))}</div>
        <div class="detail">task=${escapeHtml(resolveTaskFromFd(session.pid) ?? 'none')}</div>
      </div>

      <h2>Terminal</h2>
      <div class="row">
        <div class="label">${escapeHtml(session.terminal ? session.terminal.name : 'not mapped')}</div>
        <div class="meta">terminalPid=${escapeHtml(terminalPid ? String(terminalPid) : 'unknown')} active=${escapeHtml(String(vscode.window.activeTerminal === session.terminal))}</div>
      </div>

      <h2>Process Chain</h2>
      ${processRows || '<div class="row"><div class="detail">(unavailable)</div></div>'}
    </body>
  </html>`;

  const panel = vscode.window.createWebviewPanel(
    'aeoVscCcSessionInfo',
    `Session Info: ${title}`,
    vscode.ViewColumn.Beside,
    {
      enableScripts: false,
      retainContextWhenHidden: false,
    },
  );
  panel.webview.html = html;

  const disposeOnBlur = panel.onDidChangeViewState(event => {
    if (!event.webviewPanel.active) {
      disposeOnBlur.dispose();
      panel.dispose();
    }
  });
}

export function activate(context: vscode.ExtensionContext): void {
  const log = vscode.window.createOutputChannel('AEO CC Sessions', { log: true });
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

  void vscode.commands.executeCommand('setContext', 'aeoVscCcSessions.runtimeMissingPlugin', false);

  const discovery = new SessionDiscovery();
  const webviewProvider = new SessionsWebviewProvider(discovery, log);
  const terminalMapper = new TerminalMapper(discovery, log);
  const transcriptResolver = new TranscriptResolver(log);
  const detectorPollInterval = vscode.workspace.getConfiguration('aeoVscCcSessions').get<number>('detectorPollInterval', 2000);
  const refreshInterval = vscode.workspace.getConfiguration('aeoVscCcSessions').get<number>('refreshInterval', 3000);
  webviewProvider.setTerminalMapper(terminalMapper);
  let installedSidecarSnapshot = {
    install: loadInstalledSidecar(),
    candidates: listInstalledSidecarCandidates(),
  };
  const detectors = new Map<string, StateDetector>();
  const sidecarStatusCache = new Map<string, string>();
  const lineageStatusCache = new Map<string, string>();
  const transcriptPresentationRefreshCache = new Map<string, { identity: string; refreshedAt: number }>();
  let lastSidecarIssueKey: string | undefined;
  const issueFirstSeenAt = new Map<string, number>();
  let lastInstallButtonDebugKey: string | undefined;
  let startupInstallAttempted = false;
  const resolvedTranscriptKey = 'resolvedTranscriptSessionIds';
  const localAliasKey = 'localSessionAliases';
  const resolvedTranscriptIds = new Map<string, string>(
    Object.entries(context.workspaceState.get<Record<string, string>>(resolvedTranscriptKey, {})),
  );
  const localAliases = new Map<string, string>(
    Object.entries(context.workspaceState.get<Record<string, string>>(localAliasKey, {})),
  );
  let pendingFocusRequests: PendingFocusRequest[] = [];
  let interactionGraceUntil = 0;
  let fullRefreshTimer: ReturnType<typeof setTimeout> | undefined;
  let fullRefreshInProgress = false;
  let fullRefreshNeedsRerun = false;
  let pendingRefreshReason: string | undefined;
  let periodicRefreshTimer: ReturnType<typeof setTimeout> | undefined;

  function loadResolvedTranscriptId(sessionId: string): string | undefined {
    return resolvedTranscriptIds.get(sessionId);
  }

  function persistResolvedTranscriptId(sessionId: string, transcriptSessionId: string): void {
    if (resolvedTranscriptIds.get(sessionId) === transcriptSessionId) return;
    resolvedTranscriptIds.set(sessionId, transcriptSessionId);
    void context.workspaceState.update(
      resolvedTranscriptKey,
      Object.fromEntries(resolvedTranscriptIds),
    );
  }

  function forgetResolvedTranscriptId(sessionId: string): void {
    if (!resolvedTranscriptIds.delete(sessionId)) return;
    void context.workspaceState.update(
      resolvedTranscriptKey,
      Object.fromEntries(resolvedTranscriptIds),
    );
  }

  function getLocalAlias(processKey: string): string | undefined {
    const alias = localAliases.get(processKey);
    return alias && alias.trim().length > 0 ? alias : undefined;
  }

  function persistLocalAlias(processKey: string, alias: string | undefined): void {
    if (!alias || alias.trim().length === 0) {
      if (!localAliases.delete(processKey)) return;
    } else {
      localAliases.set(processKey, alias.trim());
    }
    void context.workspaceState.update(
      localAliasKey,
      Object.fromEntries(localAliases),
    );
  }

  function forgetLocalAlias(processKey: string): void {
    if (!localAliases.delete(processKey)) return;
    void context.workspaceState.update(
      localAliasKey,
      Object.fromEntries(localAliases),
    );
  }

  function applyLocalAlias(session: SessionInfo): void {
    session.localAlias = getLocalAlias(session.processKey);
  }

  function refreshInstalledSidecarSnapshot(): void {
    installedSidecarSnapshot = {
      install: loadInstalledSidecar(),
      candidates: listInstalledSidecarCandidates(),
    };
  }

  function updateInstallButtonContext(): void {
    const { install, candidates } = installedSidecarSnapshot;
    const debugKey = JSON.stringify({
      health: install.health,
      message: install.message,
      candidates: candidates.map(candidate => ({
        key: candidate.key,
        scope: candidate.scope,
        version: candidate.version,
        accepted: candidate.accepted,
        reason: candidate.reason,
      })),
    });
    if (lastInstallButtonDebugKey !== debugKey) {
      lastInstallButtonDebugKey = debugKey;
      if (candidates.length === 0) {
        log.info(`Install button context: health=${install.health} reason=${install.message} candidates=none`);
      } else {
        const candidateSummary = candidates
          .map(candidate => `${candidate.key} source=${candidate.source} scope=${candidate.scope} accepted=${candidate.accepted} reason=${candidate.reason} version=${candidate.version ?? 'unknown'}`)
          .join(' | ');
        log.info(`Install button context: health=${install.health} reason=${install.message} candidates=${candidateSummary}`);
      }
    }
    void vscode.commands.executeCommand(
      'setContext',
      'aeoVscCcSessions.runtimeMissingPlugin',
      install.health === 'missing-plugin' || install.health === 'disabled',
    );
  }

  function applyAndLogSidecarAssessment(session: SessionInfo): void {
    const { install } = installedSidecarSnapshot;
    const installStatus = `${install.health}:${install.message}`;
    if (sidecarStatusCache.get('__install__') !== installStatus) {
      sidecarStatusCache.set('__install__', installStatus);
      log.info(`Claude runtime install ${install.health}: ${install.message}`);
    }

    const assessment = assessSidecarForSession(session, install);
    const status = `${assessment.health}:${assessment.message}`;
    if (sidecarStatusCache.get(session.processKey) !== status) {
      sidecarStatusCache.set(session.processKey, status);
      log.info(`Claude runtime ${session.processKey} ${assessment.health}: ${assessment.message}`);
    }
    const previousSessionId = session.sessionId;
    const previousTranscriptPath = session.transcriptPath;
    const previousStartSource = session.startSource;
    const previousPreviousTranscriptSessionId = session.previousTranscriptSessionId;
    const previousPreviousTranscriptPath = session.previousTranscriptPath;
    const changed = applySidecarAssessment(session, assessment);
    const forcePresentationRefresh = previousSessionId !== session.sessionId
      || previousTranscriptPath !== session.transcriptPath;
    refreshTranscriptPresentationForSession(session, forcePresentationRefresh);
    if (assessment.health === 'healthy' && assessment.state?.current_session_id) {
      persistResolvedTranscriptId(session.processKey, assessment.state.current_session_id);
    }
    const lineageChanged = previousSessionId !== session.sessionId
      || previousTranscriptPath !== session.transcriptPath
      || previousStartSource !== session.startSource
      || previousPreviousTranscriptSessionId !== session.previousTranscriptSessionId
      || previousPreviousTranscriptPath !== session.previousTranscriptPath;
    if (
      changed
      && assessment.health === 'healthy'
      && session.startSource
      && lineageChanged
    ) {
      const lineageSignature = [
        session.startSource,
        session.sessionId,
        session.transcriptPath ?? '',
        session.previousTranscriptSessionId ?? '',
        session.previousTranscriptPath ?? '',
      ].join('|');
      if (lineageStatusCache.get(session.processKey) !== lineageSignature) {
        lineageStatusCache.set(session.processKey, lineageSignature);
        log.info(
          `Claude runtime lineage ${session.processKey} source=${session.startSource} current=${session.sessionId.slice(0, 8)} previous=${session.previousTranscriptSessionId?.slice(0, 8) ?? 'none'}`,
        );
      }
    }
  }

  function refreshSidecarState(): void {
    for (const session of discovery.getSessions().values()) {
      applyAndLogSidecarAssessment(session);
    }
  }

  function refreshTranscriptPresentation(): void {
    for (const session of discovery.getSessions().values()) {
      refreshTranscriptPresentationForSession(session);
    }
  }

  function refreshTranscriptPresentationForSession(session: SessionInfo, force = false): void {
    const identity = `${session.transcriptSessionId ?? session.sessionId}|${session.transcriptPath ?? ''}`;
    const previous = transcriptPresentationRefreshCache.get(session.processKey);
    const now = Date.now();
    const needsPresentation = !session.customTitle && !session.agentName;
    if (
      !force
      && previous
      && previous.identity === identity
      && !needsPresentation
      && now - previous.refreshedAt < TRANSCRIPT_PRESENTATION_REFRESH_TTL_MS
    ) {
      return;
    }

    const meta = transcriptResolver.getSessionPresentation(
      session.cwd,
      session.transcriptSessionId ?? session.sessionId,
      session.transcriptPath,
    );
    session.customTitle = meta?.customTitle ?? undefined;
    session.agentName = meta?.agentName ?? undefined;
    session.slug = meta?.slug ?? session.registrySlug ?? undefined;
    applyLocalAlias(session);
    transcriptPresentationRefreshCache.set(session.processKey, {
      identity,
      refreshedAt: now,
    });
  }

  function primeSidecarState(session: SessionInfo): void {
    applyLocalAlias(session);
    applyAndLogSidecarAssessment(session);
  }

  function summarizeSidecarIssue(): {
    key: string;
    kind: 'install' | 'runtime';
    severity: 'warning' | 'error';
    message: string;
    tooltip: string;
    notify: boolean;
  } | undefined {
    const { install } = installedSidecarSnapshot;
    if (install.health !== 'healthy') {
      const severity = install.health === 'invalid' || install.health === 'plugin-conflict'
        ? 'error'
        : 'warning';
      return {
        key: `install:${install.health}:${install.message}`,
        kind: 'install',
        severity,
        message: `AEO CC Sessions runtime ${install.health.replace(/-/g, ' ')}.`,
        tooltip: install.message,
        notify: true,
      };
    }

    const liveUnhealthy = [...discovery.getSessions().values()]
      .filter(session => session.state !== 'exited')
      .filter(session => session.sidecarHealth && !['healthy', 'starting'].includes(session.sidecarHealth));

    if (liveUnhealthy.length === 0) return undefined;

    const counts = new Map<string, number>();
    for (const session of liveUnhealthy) {
      const health = session.sidecarHealth ?? 'unknown';
      counts.set(health, (counts.get(health) ?? 0) + 1);
    }
    const summary = [...counts.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([health, count]) => `${health}:${count}`)
      .join(',');
    const severity = liveUnhealthy.some(session => session.sidecarHealth === 'invalid')
      ? 'error'
      : 'warning';
    const tooltip = liveUnhealthy
      .slice(0, 6)
      .map(session => `${session.processKey} ${session.sidecarHealth}: ${session.sidecarMessage ?? ''}`.trim())
      .join('\n');
    const singleDetail = liveUnhealthy.length === 1
      ? liveUnhealthy[0].sidecarMessage?.trim()
      : undefined;
    return {
      key: `runtime:${summary}`,
      kind: 'runtime',
      severity,
      message: singleDetail
        ? `AEO CC Sessions runtime issue: ${singleDetail}`
        : `AEO CC Sessions runtime is unhealthy for ${liveUnhealthy.length} live Claude session${liveUnhealthy.length === 1 ? '' : 's'}.`,
      tooltip,
      notify: Boolean(singleDetail),
    };
  }

  async function showSidecarIssueNotification(issue: {
    key: string;
    kind: 'install' | 'runtime';
    severity: 'warning' | 'error';
    message: string;
    tooltip: string;
    notify: boolean;
  }): Promise<void> {
    const summary = `${issue.key} | ${issue.message}${issue.tooltip ? ` | ${issue.tooltip}` : ''}`;
    if (issue.severity === 'error') {
      log.error(`Runtime issue popup: ${summary}`);
    } else {
      log.warn(`Runtime issue popup: ${summary}`);
    }
    const actions = issue.kind === 'install'
      ? ['Install/Update Runtime', 'Open Logs', 'Don\'t Show Again']
      : ['Validate Runtime', 'Open Logs', 'Don\'t Show Again'];
    const selected = issue.severity === 'error'
      ? await vscode.window.showErrorMessage(issue.message, ...actions)
      : await vscode.window.showWarningMessage(issue.message, ...actions);

    if (selected === 'Validate Runtime') {
      await vscode.commands.executeCommand('aeoVscCcSessions.validateSidecarHealth');
    } else if (selected === 'Open Logs') {
      log.show(true);
    } else if (selected === 'Install/Update Runtime') {
      await vscode.commands.executeCommand('aeoVscCcSessions.installSidecarPlugin');
    } else if (selected === 'Don\'t Show Again') {
      await context.globalState.update('sidecarIssueNotificationsMuted', true);
    }
  }

  function updateSidecarIssueSurface(): void {
    const muted = context.globalState.get<boolean>('sidecarIssueNotificationsMuted', false);
    updateInstallButtonContext();
    const issue = summarizeSidecarIssue();
    if (!issue) {
      lastSidecarIssueKey = undefined;
      issueFirstSeenAt.clear();
      return;
    }

    if (!issueFirstSeenAt.has(issue.key)) {
      issueFirstSeenAt.set(issue.key, Date.now());
    }

    if (!muted && lastSidecarIssueKey !== issue.key) {
      if (issue.kind === 'runtime' && issue.notify) {
        const firstSeenAt = issueFirstSeenAt.get(issue.key) ?? Date.now();
        if (Date.now() - firstSeenAt < RUNTIME_ISSUE_NOTIFY_DELAY_MS) {
          return;
        }
      }
      lastSidecarIssueKey = issue.key;
      if (issue.notify) {
        void showSidecarIssueNotification(issue);
      }
      return;
    }
    lastSidecarIssueKey = issue.key;
  }

  function scheduleNextPeriodicRefresh(delayMs = refreshInterval): void {
    if (periodicRefreshTimer) {
      clearTimeout(periodicRefreshTimer);
    }
    const now = Date.now();
    const interactionDelay = interactionGraceUntil > now
      ? interactionGraceUntil - now
      : 0;
    const effectiveDelay = Math.max(delayMs, interactionDelay);
    periodicRefreshTimer = setTimeout(() => {
      periodicRefreshTimer = undefined;
      scheduleFullRefresh('periodic');
    }, effectiveDelay);
  }

  function runFullRefresh(reason: string): void {
    const startedAt = Date.now();
    refreshSidecarState();
    refreshTranscriptPresentation();
    updateSidecarIssueSurface();
    webviewProvider.refresh();
    log.debug(`full-refresh reason=${reason} durationMs=${Date.now() - startedAt}`);
  }

  function scheduleFullRefresh(
    reason: string,
    options?: { delayMs?: number; deferDuringInteraction?: boolean },
  ): void {
    pendingRefreshReason = reason;
    if (fullRefreshInProgress) {
      fullRefreshNeedsRerun = true;
      return;
    }

    const now = Date.now();
    let delayMs = options?.delayMs ?? 0;
    if (options?.deferDuringInteraction && interactionGraceUntil > now) {
      delayMs = Math.max(delayMs, interactionGraceUntil - now);
    }

    if (fullRefreshTimer) {
      clearTimeout(fullRefreshTimer);
    }
    fullRefreshTimer = setTimeout(() => {
      fullRefreshTimer = undefined;
      const activeReason = pendingRefreshReason ?? reason;
      pendingRefreshReason = undefined;
      fullRefreshInProgress = true;
      try {
        runFullRefresh(activeReason);
      } finally {
        fullRefreshInProgress = false;
        if (fullRefreshNeedsRerun) {
          fullRefreshNeedsRerun = false;
          scheduleFullRefresh(pendingRefreshReason ?? `${activeReason}:rerun`);
          return;
        }
        scheduleNextPeriodicRefresh();
      }
    }, delayMs);
  }

  const bothProviders = {
    refresh(reason = 'coalesced') {
      scheduleFullRefresh(reason);
    },
    refreshNow(reason = 'immediate') {
      scheduleFullRefresh(reason);
    },
  };

  function maybeInstallRuntimeOnStartup(): void {
    if (startupInstallAttempted) return;
    const { install } = installedSidecarSnapshot;
    if (install.health !== 'missing-plugin') {
      log.info(`Startup runtime install skipped: health=${install.health} reason=${install.message}`);
      return;
    }

    startupInstallAttempted = true;
    log.info(`Startup runtime install triggered: health=${install.health}`);
    void (async () => {
      const results = await installOrUpdateRuntime(context, log);
      refreshInstalledSidecarSnapshot();
      updateInstallButtonContext();
      bothProviders.refreshNow('startup-install');
      const failed = results.find(result => result.code !== 0);
      if (failed) {
        log.warn(`Startup runtime install failed at step=${failed.step} code=${failed.code}`);
        return;
      }
      log.info('Startup runtime install succeeded. Restart Claude sessions to load the new hooks.');
    })();
  }

  const webviewReg = vscode.window.registerWebviewViewProvider('aeoVscCcSessionsRich', webviewProvider);
  updateInstallButtonContext();

  const focusCmd = vscode.commands.registerCommand('aeoVscCcSessions.focusSession', async (target: unknown) => {
    const args = resolveFocusSessionCommandArgs(target);
    if (!args) {
      log.warn(`focus-trace trace=${JSON.stringify(null)} stage=${JSON.stringify('command.focus.invalid-target')} target=${JSON.stringify(String(target))}`);
      return;
    }
    const { processKey, traceId, pointerDownAt, clickAt, webviewReceivedAt } = args;
    const requestedAt = Date.now();
    interactionGraceUntil = requestedAt + INTERACTION_REFRESH_GRACE_MS;
    pendingFocusRequests.push({ ...args, requestedAt });
    logFocusTrace(log, traceId, 'command.focus.start', {
      processKey,
      pointerDownToCommandMs: typeof pointerDownAt === 'number' ? requestedAt - pointerDownAt : undefined,
      clickToCommandMs: typeof clickAt === 'number' ? requestedAt - clickAt : undefined,
      receiveToCommandMs: typeof webviewReceivedAt === 'number' ? requestedAt - webviewReceivedAt : undefined,
      pendingRequests: pendingFocusRequests.length,
    });
    log.info(`Focus Session requested: ${processKey}`);
    const result = await terminalMapper.focusSession(processKey, traceId);
    if (result.status === 'already-active') {
      pendingFocusRequests = pendingFocusRequests.filter(request => request.traceId !== traceId);
      logFocusTrace(log, traceId, 'command.focus.already-active', {
        processKey,
        targetTerminalName: result.targetTerminalName,
        totalMs: Date.now() - requestedAt,
      });
    }
    log.info(`Focus Session handler returned: ${processKey} after ${Date.now() - requestedAt}ms`);
    logFocusTrace(log, traceId, 'command.focus.return', {
      processKey,
      status: result.status,
      targetTerminalName: result.targetTerminalName,
      totalMs: Date.now() - requestedAt,
    });
  });

  const forkSessionCmd = vscode.commands.registerCommand('aeoVscCcSessions.forkSession', async (target: unknown) => {
    const session = resolveSessionTarget(discovery, target);
    if (!session) {
      void vscode.window.showErrorMessage('Session not found.');
      return;
    }

    try {
      const forkCommand = buildForkSessionCommand(session);
      launchClaudeTerminal(forkCommand);
      log.info(`Fork Session launched: ${session.processKey} resume=${forkCommand.resumeSessionId}`);
    } catch (error) {
      void vscode.window.showErrorMessage(
        error instanceof Error ? error.message : String(error),
      );
    }
  });

  const newSessionCmd = vscode.commands.registerCommand('aeoVscCcSessions.newSession', async () => {
    try {
      const newSessionCommand = buildNewSessionCommand();
      launchClaudeTerminal(newSessionCommand);
      log.info(`New Session launched: cwd=${newSessionCommand.cwd} cmd=${newSessionCommand.terminalCommand}`);
    } catch (error) {
      void vscode.window.showErrorMessage(
        error instanceof Error ? error.message : String(error),
      );
    }
  });

  const sessionInfoCmd = vscode.commands.registerCommand('aeoVscCcSessions.sessionInfo', async (target: unknown) => {
    const session = resolveSessionTarget(discovery, target);
    if (!session) {
      void vscode.window.showErrorMessage('Session not found.');
      return;
    }
    try {
      await showSessionInfo(session, transcriptResolver);
    } catch (error) {
      void vscode.window.showErrorMessage(
        error instanceof Error ? error.message : String(error),
      );
    }
  });

  const copySessionCmd = vscode.commands.registerCommand('aeoVscCcSessions.copySession', async (target: unknown) => {
    const session = resolveSessionTarget(discovery, target);
    if (!session) {
      void vscode.window.showErrorMessage('Session not found.');
      return;
    }
    try {
      const forkCommand = buildForkSessionCommand(session);
      await vscode.env.clipboard.writeText(forkCommand.shellCommand);
      void vscode.window.showInformationMessage('Fork Session command copied.');
    } catch (error) {
      void vscode.window.showErrorMessage(
        error instanceof Error ? error.message : String(error),
      );
    }
  });

  const renameSessionCmd = vscode.commands.registerCommand('aeoVscCcSessions.renameSessionEntry', async (target: unknown) => {
    const session = resolveSessionTarget(discovery, target);
    if (!session) {
      void vscode.window.showErrorMessage('Session not found.');
      return;
    }

    const currentAlias = getLocalAlias(session.processKey) ?? '';
    const currentDisplayName = getSessionDisplayName(session);
    const value = await vscode.window.showInputBox({
      title: 'Rename Session Entry',
      prompt: 'Set a local panel name for this running Claude process. Leave empty to clear it.',
      value: currentAlias,
      valueSelection: [0, currentAlias.length],
      placeHolder: currentDisplayName,
      ignoreFocusOut: true,
    });
    if (value === undefined) {
      return;
    }

    const nextAlias = value.trim();
    persistLocalAlias(session.processKey, nextAlias || undefined);
    const liveSession = discovery.getSession(session.processKey);
    if (liveSession) {
      liveSession.localAlias = nextAlias || undefined;
    }
    bothProviders.refreshNow('rename-session-entry');
    log.info(`Rename Session Entry: ${session.processKey} alias=${nextAlias || '(cleared)'}`);
  });

  const closeSessionCmd = vscode.commands.registerCommand('aeoVscCcSessions.closeSession', async (target: unknown) => {
    const session = resolveSessionTarget(discovery, target);
    if (!session) {
      void vscode.window.showErrorMessage('Session not found.');
      return;
    }

    const closed = await terminalMapper.closeSession(session.processKey);
    if (!closed) {
      void vscode.window.showErrorMessage('No mapped terminal was found for this session.');
      return;
    }
    log.info(`Close Session requested: ${session.processKey}`);
  });

  const installSidecarCmd = vscode.commands.registerCommand('aeoVscCcSessions.installSidecarPlugin', async () => {
    const results = await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: 'Installing AEO CC Sessions runtime…',
        cancellable: false,
      },
      async progress => {
        progress.report({ message: 'Adding marketplace and installing plugin…' });
        return installOrUpdateRuntime(context, log);
      },
    );
    refreshInstalledSidecarSnapshot();
    updateInstallButtonContext();
    bothProviders.refreshNow('install-command');
    const failed = results.find(result => result.code !== 0);
    if (failed) {
      const failure = describeInstallFailure(failed);
      const action = await vscode.window.showErrorMessage(
        failure.title,
        { modal: true, detail: failure.detail },
        ...failure.actions.map(title => ({ title })),
      );
      if (action?.title === 'Retry Install') {
        await vscode.commands.executeCommand('aeoVscCcSessions.installSidecarPlugin');
      } else if (action?.title === 'Open Logs') {
        log.show(true);
      } else if (action?.title === 'Open Marketplace') {
        await vscode.env.openExternal(vscode.Uri.parse(SIDECAR_MARKETPLACE_SOURCE));
      }
      return;
    }
    void vscode.window.showInformationMessage('Claude runtime installed or updated. Restart Claude sessions to load the new hooks.');
  });

  const validateSidecarCmd = vscode.commands.registerCommand('aeoVscCcSessions.validateSidecarHealth', async () => {
    const { install } = installedSidecarSnapshot;
    log.info(`Validate Claude runtime install ${install.health}: ${install.message}`);
    const lines: string[] = [`install=${install.health} ${install.message}`];
    for (const session of discovery.getSessions().values()) {
      const assessment = assessSidecarForSession(session, install);
      lines.push(`${session.processKey} sid=${session.sessionId.slice(0, 8)} ${assessment.health} ${assessment.message}`);
      log.info(`Validate Claude runtime session ${session.processKey}: ${assessment.health} ${assessment.message}`);
    }
    bothProviders.refreshNow('validate-command');
    void vscode.window.showInformationMessage(`Claude runtime validation complete. ${lines.join(' | ')}`);
  });

  const removeSidecarCmd = vscode.commands.registerCommand('aeoVscCcSessions.removeSidecarPlugin', async () => {
    const results = await removeBundledSidecar(log, discovery.getSessions().values());
    refreshInstalledSidecarSnapshot();
    updateInstallButtonContext();
    bothProviders.refreshNow('remove-command');
    const uninstallFailed = results.find(result => result.step === 'plugin_uninstall' && result.code !== 0);
    const disableSucceeded = results.some(result => result.step === 'plugin_disable' && result.code === 0);
    const failed = disableSucceeded
      ? results.find(result => result.step !== 'plugin_uninstall' && result.code !== 0)
      : results.find(result => result.code !== 0);
    if (failed) {
      void vscode.window.showErrorMessage(`Claude runtime removal fallback failed: ${failed.stderr || failed.stdout}`);
      return;
    }
    if (uninstallFailed && !disableSucceeded) {
      void vscode.window.showErrorMessage(`Claude runtime removal fallback failed: ${uninstallFailed.stderr || uninstallFailed.stdout}`);
      return;
    }
    void vscode.window.showInformationMessage('Claude runtime removed or disabled.');
  });

  const matchSub = terminalMapper.onDidMatch(() => bothProviders.refresh('terminal-match'));
  const activeTermSub = vscode.window.onDidChangeActiveTerminal(() => {
    const activeIds = [...terminalMapper.getActiveSessionIds()];
    if (pendingFocusRequests.length > 0) {
      const changedAt = Date.now();
      for (const request of pendingFocusRequests) {
        const matched = activeIds.includes(request.processKey);
        const delta = changedAt - request.requestedAt;
        log.info(`Active terminal changed after ${delta}ms | requested=${request.processKey} matched=${matched} activeIds=${activeIds.join(',') || 'none'}`);
        logFocusTrace(log, request.traceId, 'window.active-terminal.changed', {
          requestedProcessKey: request.processKey,
          matched,
          totalMs: delta,
          pointerDownToActiveMs: typeof request.pointerDownAt === 'number' ? changedAt - request.pointerDownAt : undefined,
          clickToActiveMs: typeof request.clickAt === 'number' ? changedAt - request.clickAt : undefined,
          receiveToActiveMs: typeof request.webviewReceivedAt === 'number' ? changedAt - request.webviewReceivedAt : undefined,
          activeIds: activeIds.join(',') || 'none',
          activeTerminalName: vscode.window.activeTerminal?.name,
        });
      }
      pendingFocusRequests = pendingFocusRequests.filter(request => (
        !activeIds.includes(request.processKey)
        && changedAt - request.requestedAt < 10000
      ));
    } else {
      log.debug(`Active terminal changed | activeIds=${activeIds.join(',') || 'none'}`);
    }
    webviewProvider.clearOptimisticVisibleIds();
    webviewProvider.refreshNow();
  });

  function ensureDetector(session: SessionInfo): void {
    if (!detectors.has(session.processKey)) {
      detectors.set(
        session.processKey,
        createDetector(
          discovery,
          bothProviders,
          session,
          transcriptResolver,
          detectorPollInterval,
          loadResolvedTranscriptId,
          persistResolvedTranscriptId,
          log,
        ),
      );
    }
  }

  const sessionSub = discovery.onDidChangeSession(event => {
    const { type, session } = event;

    if (type === 'added') {
      log.debug(`Session added: ${session.processKey} sid=${session.sessionId.slice(0, 8)} pid=${session.pid}`);
      primeSidecarState(session);
      if (session.state !== 'exited') {
        ensureDetector(session);
      }
      void terminalMapper.matchAll();
      bothProviders.refresh('session-added');
    } else if (type === 'removed') {
      log.debug(`Session removed: ${session.processKey} sid=${session.sessionId.slice(0, 8)}`);
      const detector = detectors.get(session.processKey);
      if (detector) {
        detector.dispose();
        detectors.delete(session.processKey);
      }
      forgetResolvedTranscriptId(session.processKey);
      forgetLocalAlias(session.processKey);
      sidecarStatusCache.delete(session.processKey);
      lineageStatusCache.delete(session.processKey);
      transcriptPresentationRefreshCache.delete(session.processKey);
      bothProviders.refresh('session-removed');
    } else {
      bothProviders.refresh('session-updated');
    }
  });

  for (const [, session] of discovery.getSessions()) {
    primeSidecarState(session);
    if (session.state !== 'exited') {
      ensureDetector(session);
    }
  }

  void terminalMapper.matchAll();
  bothProviders.refreshNow('startup');
  maybeInstallRuntimeOnStartup();

  context.subscriptions.push(
    discovery,
    webviewProvider,
    terminalMapper,
    webviewReg,
    focusCmd,
    forkSessionCmd,
    newSessionCmd,
    sessionInfoCmd,
    copySessionCmd,
    renameSessionCmd,
    closeSessionCmd,
    installSidecarCmd,
    validateSidecarCmd,
    removeSidecarCmd,
    sessionSub,
    matchSub,
    activeTermSub,
    {
      dispose: () => {
        if (periodicRefreshTimer) {
          clearTimeout(periodicRefreshTimer);
          periodicRefreshTimer = undefined;
        }
      },
    },
    { dispose: () => { for (const d of detectors.values()) d.dispose(); detectors.clear(); } },
  );
}

export function deactivate(): void {}
