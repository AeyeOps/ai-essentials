import * as vscode from 'vscode';

export type SessionState =
  | 'starting'
  | 'idle'
  | 'thinking'
  | 'tool'
  | 'prompt'
  | 'permission'
  | 'compact'
  | 'error'
  | 'exited';

export type SidecarHealth =
  | 'healthy'
  | 'starting'
  | 'missing-plugin'
  | 'disabled'
  | 'plugin-conflict'
  | 'missing-state'
  | 'stale'
  | 'invalid';

export interface SessionInfo {
  processKey: string;
  pid: number;
  pidStartTicks: number;
  sessionId: string;
  registrySessionId?: string;
  cwd: string;
  startedAt: number;
  observedAt: number;
  transcriptSessionId?: string;
  transcriptPath?: string;
  startSource?: string;
  previousTranscriptSessionId?: string;
  previousTranscriptPath?: string;
  state: SessionState;
  toolName?: string;
  toolDetail?: string;
  activeSubagentCount?: number;
  sidecarHealth?: SidecarHealth;
  sidecarMessage?: string;
  sidecarUpdatedAt?: number;
  stateChangedAt: number;
  terminal?: vscode.Terminal;
  localAlias?: string;
  registrySlug?: string;
  customTitle?: string;
  agentName?: string;
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
