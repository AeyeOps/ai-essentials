import * as vscode from 'vscode';
import * as path from 'node:path';
import type { SessionInfo, SessionState } from './types.js';

export function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  if (totalSeconds < 60) return `${totalSeconds}s`;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes < 60) return `${minutes}m ${seconds}s`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m`;
}

export const stateSortOrder: Record<SessionState, number> = {
  starting: 0,
  prompt: 1,
  permission: 2,
  tool: 3,
  thinking: 4,
  compact: 5,
  idle: 6,
  error: 7,
  exited: 8,
};

export type RichSortMode = 'none' | 'name' | 'state';

export function getSessionDisplayName(session: SessionInfo): string {
  const candidates = [
    session.localAlias,
    session.customTitle,
    session.agentName,
    path.basename(session.cwd),
    session.cwd,
  ];
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim().length > 0) {
      return candidate.trim();
    }
  }
  return 'Session';
}

export function getSessionShortId(session: SessionInfo): string {
  const currentId = session.sessionId || session.transcriptSessionId || '';
  if (currentId.length <= 6) return currentId || 'unknown';
  return `…${currentId.slice(-6)}`;
}

export function getSessionAgeText(session: SessionInfo): string {
  return formatDuration(Math.max(0, Date.now() - session.startedAt));
}

export function getSubagentSummary(count: number | undefined): string | undefined {
  if (!count || count <= 0) return undefined;
  return count === 1 ? '1 subagent' : `${count} subagents`;
}

function isAnonymousWorkerCandidate(session: SessionInfo): boolean {
  const hasPresentationIdentity = Boolean(
    session.localAlias
    || session.customTitle
    || session.agentName
    || session.slug,
  );

  if (hasPresentationIdentity) return false;
  if ((session.activeSubagentCount ?? 0) > 0) return false;
  if (session.state === 'exited') return false;
  return true;
}

function compareSessionsStable(a: SessionInfo, b: SessionInfo): number {
  if (a.startedAt !== b.startedAt) {
    return a.startedAt - b.startedAt;
  }

  const aTerminalIndex = a.terminal ? vscode.window.terminals.indexOf(a.terminal) : -1;
  const bTerminalIndex = b.terminal ? vscode.window.terminals.indexOf(b.terminal) : -1;
  if (aTerminalIndex !== bTerminalIndex) {
    if (aTerminalIndex === -1) return 1;
    if (bTerminalIndex === -1) return -1;
    return aTerminalIndex - bTerminalIndex;
  }

  return a.processKey.localeCompare(b.processKey);
}

export function getStatusText(session: SessionInfo): string {
  const elapsed = Date.now() - session.stateChangedAt;
  switch (session.state) {
    case 'starting':
      return session.sidecarMessage ?? 'Starting Claude runtime...';
    case 'idle': return `Idle ${formatDuration(elapsed)}`;
    case 'thinking': return elapsed > 3000 ? `Thinking ${formatDuration(elapsed)}...` : 'Thinking...';
    case 'tool':
      if (session.toolName && session.toolDetail) return `${session.toolName}: ${session.toolDetail}`;
      return session.toolName ?? 'Tool';
    case 'prompt':
      if (session.toolDetail) return `Needs input: ${session.toolDetail}`;
      return 'Needs your input';
    case 'permission': return 'Waiting for permission...';
    case 'compact':
      if (session.toolDetail) return `Compact: ${session.toolDetail}`;
      return 'Compacting context...';
    case 'error': return session.toolDetail ?? session.sidecarMessage ?? 'Runtime error';
    case 'exited': return 'Exited';
  }
}

export function getFilteredSortedSessions(
  discovery: { getSessions(): Map<string, SessionInfo> },
  terminalMapper: { isOwnSessionSync(pid: number): boolean } | undefined,
): SessionInfo[] {
  const showExited = vscode.workspace.getConfiguration('aeoVscCcSessions').get<boolean>('showExited', false);
  const sessions = [...discovery.getSessions().values()];

  const filtered = sessions.filter(s => {
    if (!terminalMapper?.isOwnSessionSync(s.pid)) return false;
    if (!showExited && s.state === 'exited') return false;
    return true;
  });

  const terminalGroups = new Map<vscode.Terminal | string, SessionInfo[]>();
  for (const session of filtered) {
    const terminalKey = session.terminal ?? `session:${session.processKey}`;
    const group = terminalGroups.get(terminalKey) ?? [];
    group.push(session);
    terminalGroups.set(terminalKey, group);
  }

  const grouped = [...terminalGroups.values()];
  for (const group of grouped) {
    group.sort(compareSessionsStable);
  }

  const suppressedIds = new Set<string>();
  for (const group of grouped) {
    const parentHasActiveSubagents = group.some(session => (session.activeSubagentCount ?? 0) > 0);
    if (!parentHasActiveSubagents) continue;

    for (const session of group) {
      if (isAnonymousWorkerCandidate(session)) {
        suppressedIds.add(session.processKey);
      }
    }
  }

  grouped.sort((a, b) => compareSessionsStable(a[0], b[0]));

  return grouped
    .flat()
    .filter(session => !suppressedIds.has(session.processKey));
}

export function getRichSortedSessions(
  sessions: SessionInfo[],
  mode: RichSortMode,
): SessionInfo[] {
  if (mode === 'none') return sessions;

  const sorted = [...sessions];
  if (mode === 'name') {
    sorted.sort((a, b) => {
      const diff = getSessionDisplayName(a).localeCompare(getSessionDisplayName(b));
      if (diff !== 0) return diff;
      return compareSessionsStable(a, b);
    });
    return sorted;
  }

  sorted.sort((a, b) => {
    const stateDiff = stateSortOrder[a.state] - stateSortOrder[b.state];
    if (stateDiff !== 0) return stateDiff;
    const nameDiff = getSessionDisplayName(a).localeCompare(getSessionDisplayName(b));
    if (nameDiff !== 0) return nameDiff;
    return compareSessionsStable(a, b);
  });
  return sorted;
}
