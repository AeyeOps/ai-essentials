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
  tool: 0, thinking: 1, permission: 2, compact: 3, idle: 4, error: 5, exited: 6,
};

export function getStatusText(session: SessionInfo): string {
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

export function getFilteredSortedSessions(
  discovery: { getSessions(): Map<string, SessionInfo> },
  terminalMapper: { isOwnSessionSync(pid: number): boolean } | undefined,
): SessionInfo[] {
  const showExited = vscode.workspace.getConfiguration('aeoVscCcSessions').get<boolean>('showExited', false);
  const sortByActivity = vscode.workspace.getConfiguration('aeoVscCcSessions').get<boolean>('sortByActivity', true);
  const sessions = [...discovery.getSessions().values()];

  const filtered = sessions.filter(s => {
    if (!terminalMapper?.isOwnSessionSync(s.pid)) return false;
    if (!showExited && s.state === 'exited') return false;
    return true;
  });

  filtered.sort((a, b) => {
    if (sortByActivity) {
      const oa = stateSortOrder[a.state], ob = stateSortOrder[b.state];
      if (oa !== ob) return oa - ob;
    }
    return a.stateChangedAt - b.stateChangedAt;
  });

  return filtered;
}
