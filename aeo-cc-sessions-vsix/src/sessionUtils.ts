import * as vscode from 'vscode';
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
  prompt: 0, tool: 1, thinking: 2, permission: 3, compact: 4, idle: 5, error: 6, exited: 7,
};

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

  return a.sessionId.localeCompare(b.sessionId);
}

export function getStatusText(session: SessionInfo): string {
  const elapsed = Date.now() - session.stateChangedAt;
  switch (session.state) {
    case 'idle': return `Idle ${formatDuration(elapsed)}`;
    case 'thinking': return elapsed > 3000 ? `Thinking ${formatDuration(elapsed)}...` : 'Thinking...';
    case 'tool':
      if (session.toolName && session.toolDetail) return `${session.toolName}: ${session.toolDetail}`;
      return session.toolName ?? 'Tool';
    case 'prompt':
      if (session.toolDetail) return `Needs input: ${session.toolDetail}`;
      return 'Needs your input';
    case 'permission': return 'Waiting for permission...';
    case 'compact': return 'Compacting context...';
    case 'error': return 'Error';
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
    const terminalKey = session.terminal ?? `session:${session.sessionId}`;
    const group = terminalGroups.get(terminalKey) ?? [];
    group.push(session);
    terminalGroups.set(terminalKey, group);
  }

  const grouped = [...terminalGroups.values()];
  for (const group of grouped) {
    group.sort(compareSessionsStable);
  }

  grouped.sort((a, b) => compareSessionsStable(a[0], b[0]));

  return grouped.flat();
}
