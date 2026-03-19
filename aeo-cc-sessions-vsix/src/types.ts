import * as vscode from 'vscode';

export type SessionState = 'idle' | 'thinking' | 'tool' | 'permission' | 'compact' | 'error' | 'exited';

export interface SessionInfo {
  pid: number;
  sessionId: string;
  cwd: string;
  startedAt: number;
  state: SessionState;
  toolName?: string;
  toolDetail?: string;
  stateChangedAt: number;
  terminal?: vscode.Terminal;
  slug?: string;
}

export interface SessionRegistryEntry {
  pid: number;
  sessionId: string;
  cwd: string;
  startedAt: number;
}

export interface SessionEvent {
  type: 'added' | 'removed' | 'updated';
  session: SessionInfo;
}
