import * as vscode from 'vscode';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type { SessionInfo, SessionEvent, SessionRegistryEntry } from './types.js';
import { readCmdlineArgs, readProcStat } from './proc.js';

export function getTranscriptPath(cwd: string, sessionId: string): string {
  const encoded = cwd.replace(/\//g, '-');
  return path.join(os.homedir(), '.claude', 'projects', encoded, `${sessionId}.jsonl`);
}

/** Parse --resume <uuid> from /proc/<pid>/cmdline. */
export function resolveConversationFromCmdline(pid: number): string | undefined {
  const args = readCmdlineArgs(pid);
  if (!args) return undefined;

  const idx = args.indexOf('--resume');
  if (idx !== -1 && idx + 1 < args.length) {
    const uuid = args[idx + 1];
    if (uuid.length >= 36) return uuid;
  }
  return undefined;
}

/** Detect --continue from /proc/<pid>/cmdline. */
export function resolveContinueFromCmdline(pid: number): boolean {
  const args = readCmdlineArgs(pid);
  return Array.isArray(args) && args.includes('--continue');
}

/** Find active task UUID from /proc/<pid>/fd/ symlinks into ~/.claude/tasks/. */
export function resolveTaskFromFd(pid: number): string | undefined {
  try {
    const fdDir = `/proc/${pid}/fd`;
    const entries = fs.readdirSync(fdDir);
    const tasksPrefix = path.join(os.homedir(), '.claude', 'tasks') + '/';
    for (const entry of entries) {
      try {
        const target = fs.readlinkSync(path.join(fdDir, entry));
        if (target.startsWith(tasksPrefix)) {
          const rest = target.slice(tasksPrefix.length);
          const slash = rest.indexOf('/');
          const uuid = slash === -1 ? rest : rest.slice(0, slash);
          if (uuid.length >= 36) return uuid;
        }
      } catch {
        continue;
      }
    }
  } catch { /* /proc not available */ }
  return undefined;
}

function findLatestTranscriptSessionId(cwd: string, processStartedAt?: number): string | undefined {
  const encoded = cwd.replace(/\//g, '-');
  const projectDir = path.join(os.homedir(), '.claude', 'projects', encoded);

  let fileNames: string[];
  try {
    fileNames = fs.readdirSync(projectDir).filter(name => name.endsWith('.jsonl'));
  } catch {
    return undefined;
  }

  const cutoffMs = typeof processStartedAt === 'number'
    ? processStartedAt + 5_000
    : Number.POSITIVE_INFINITY;

  let best: { sessionId: string; score: number } | undefined;
  for (const name of fileNames) {
    try {
      const filePath = path.join(projectDir, name);
      const stat = fs.statSync(filePath);
      if (stat.mtimeMs > cutoffMs) continue;

      const sessionId = path.basename(name, '.jsonl');
      if (!best || stat.mtimeMs > best.score) {
        best = { sessionId, score: stat.mtimeMs };
      }
    } catch {
      continue;
    }
  }

  return best?.sessionId;
}

/**
 * Resolve the transcript path for a session, trying in order:
 * 1. --resume <uuid> from cmdline (conversation ID)
 * 2. Active task from /proc/fd/ (plan mode)
 * 3. --continue latest transcript in project at launch time
 * 4. Registry sessionId (original conversation)
 */
export function resolveTranscriptPath(
  pid: number,
  cwd: string,
  registrySessionId: string,
  processStartedAt?: number,
): string {
  const continueSessionId = resolveContinueFromCmdline(pid)
    ? findLatestTranscriptSessionId(cwd, processStartedAt)
    : undefined;
  const conversationId = resolveConversationFromCmdline(pid)
    ?? resolveTaskFromFd(pid)
    ?? continueSessionId
    ?? registrySessionId;
  return getTranscriptPath(cwd, conversationId);
}

function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export class SessionDiscovery implements vscode.Disposable {
  private readonly sessions = new Map<string, SessionInfo>();
  private readonly sessionsDir: string;
  private readonly watcher: vscode.FileSystemWatcher;
  private readonly _onDidChangeSession = new vscode.EventEmitter<SessionEvent>();
  readonly onDidChangeSession: vscode.Event<SessionEvent> = this._onDidChangeSession.event;
  private scanTimer: ReturnType<typeof setTimeout> | undefined;
  private disposed = false;

  constructor() {
    this.sessionsDir = path.join(os.homedir(), '.claude', 'sessions');

    const pattern = new vscode.RelativePattern(vscode.Uri.file(this.sessionsDir), '*.json');
    this.watcher = vscode.workspace.createFileSystemWatcher(pattern);

    this.watcher.onDidCreate(() => this.debouncedScan());
    this.watcher.onDidChange(() => this.debouncedScan());
    this.watcher.onDidDelete(() => this.debouncedScan());

    void this.scanSessions();
  }

  private debouncedScan(): void {
    if (this.disposed) return;
    if (this.scanTimer) clearTimeout(this.scanTimer);
    this.scanTimer = setTimeout(() => {
      if (!this.disposed) void this.scanSessions();
    }, 200);
  }

  async scanSessions(): Promise<void> {
    if (this.disposed) return;

    let files: string[];
    try {
      files = (await fs.promises.readdir(this.sessionsDir))
        .filter(f => f.endsWith('.json'));
    } catch {
      return;
    }

    const seen = new Set<string>();

    for (const file of files) {
      if (this.disposed) return;
      try {
        const raw = await fs.promises.readFile(path.join(this.sessionsDir, file), 'utf-8');
        const entry: SessionRegistryEntry & { slug?: string } = JSON.parse(raw);
        if (!entry.pid || !entry.sessionId || !entry.cwd) continue;

        const alive = isPidAlive(entry.pid);
        const proc = readProcStat(entry.pid);
        const existingExitedMatch = [...this.sessions.values()].find(session =>
          session.pid === entry.pid
          && session.sessionId === entry.sessionId
          && session.cwd === entry.cwd
          && session.state === 'exited',
        );
        if (!proc?.startTicks && !existingExitedMatch) continue;

        const processKey = proc?.startTicks
          ? `${entry.pid}:${proc.startTicks}`
          : existingExitedMatch!.processKey;
        seen.add(processKey);
        const existing = proc?.startTicks
          ? this.sessions.get(processKey)
          : existingExitedMatch;

        if (
          proc?.startTicks
          && existing
          && existing.state !== 'exited'
          && existing.startedAt !== entry.startedAt
        ) {
          continue;
        }

        if (existing) {
          const sessionChanged = existing.sessionId !== entry.sessionId;
          const cwdChanged = existing.cwd !== entry.cwd;
          const slugChanged = existing.slug !== (entry.slug || undefined);
          existing.sessionId = entry.sessionId;
          existing.registrySessionId = entry.sessionId;
          existing.pid = entry.pid;
          if (proc?.startTicks) {
            existing.pidStartTicks = proc.startTicks;
          }
          existing.processKey = processKey;
          existing.cwd = entry.cwd;
          existing.startedAt = entry.startedAt;
          existing.registrySlug = entry.slug || undefined;
          existing.slug = entry.slug || undefined;
          if (!alive && existing.state !== 'exited') {
            existing.state = 'exited';
            existing.stateChangedAt = Date.now();
            this._onDidChangeSession.fire({ type: 'updated', session: existing });
          } else if (sessionChanged || cwdChanged || slugChanged) {
            this._onDidChangeSession.fire({ type: 'updated', session: existing });
          }
        } else {
          const session: SessionInfo = {
            processKey,
            pid: entry.pid,
            pidStartTicks: proc!.startTicks,
            sessionId: entry.sessionId,
            registrySessionId: entry.sessionId,
            registrySlug: entry.slug || undefined,
            customTitle: undefined,
            agentName: undefined,
            cwd: entry.cwd,
            startedAt: entry.startedAt,
            observedAt: Date.now(),
            state: alive ? 'idle' : 'exited',
            stateChangedAt: Date.now(),
            slug: entry.slug || undefined,
          };
          this.sessions.set(processKey, session);
          this._onDidChangeSession.fire({ type: 'added', session });
        }
      } catch {
        // skip unparseable files
      }
    }

    for (const [id, session] of this.sessions) {
      if (!seen.has(id)) {
        if (session.state !== 'exited') {
          session.state = 'exited';
          session.stateChangedAt = Date.now();
        }
        this.sessions.delete(id);
        this._onDidChangeSession.fire({ type: 'removed', session });
      }
    }
  }

  getSessions(): Map<string, SessionInfo> {
    return this.sessions;
  }

  getSession(sessionId: string): SessionInfo | undefined {
    return this.sessions.get(sessionId);
  }

  dispose(): void {
    this.disposed = true;
    if (this.scanTimer) clearTimeout(this.scanTimer);
    this.watcher.dispose();
    this._onDidChangeSession.dispose();
    this.sessions.clear();
  }
}
