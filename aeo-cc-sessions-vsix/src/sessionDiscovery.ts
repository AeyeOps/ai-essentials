import * as vscode from 'vscode';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type { SessionInfo, SessionEvent, SessionRegistryEntry } from './types.js';

export function getTranscriptPath(cwd: string, sessionId: string): string {
  const encoded = cwd.replace(/\//g, '-');
  return path.join(os.homedir(), '.claude', 'projects', encoded, `${sessionId}.jsonl`);
}

export function resolveActiveSessionId(pid: number): string | undefined {
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
  } catch {
    // /proc not available or permission denied
  }
  return undefined;
}

export function resolveTranscriptPath(pid: number, cwd: string, registrySessionId: string): string {
  const activeId = resolveActiveSessionId(pid);
  return getTranscriptPath(cwd, activeId ?? registrySessionId);
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

        seen.add(entry.sessionId);
        const alive = isPidAlive(entry.pid);
        const existing = this.sessions.get(entry.sessionId);

        if (existing) {
          if (!alive && existing.state !== 'exited') {
            existing.state = 'exited';
            existing.stateChangedAt = Date.now();
            this._onDidChangeSession.fire({ type: 'updated', session: existing });
          }
          if (entry.slug && !existing.slug) {
            existing.slug = entry.slug;
          }
        } else {
          const session: SessionInfo = {
            pid: entry.pid,
            sessionId: entry.sessionId,
            cwd: entry.cwd,
            startedAt: entry.startedAt,
            state: alive ? 'idle' : 'exited',
            stateChangedAt: Date.now(),
            slug: entry.slug,
          };
          this.sessions.set(entry.sessionId, session);
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
