import * as vscode from 'vscode';
import * as fs from 'node:fs';
import type { SessionDiscovery } from './sessionDiscovery.js';

function readPpid(pid: number): number | undefined {
  try {
    const raw = fs.readFileSync(`/proc/${pid}/stat`, 'utf-8');
    const closeParen = raw.lastIndexOf(')');
    if (closeParen === -1) return undefined;
    const fields = raw.slice(closeParen + 2).split(' ');
    const ppid = parseInt(fields[1], 10);
    return Number.isNaN(ppid) ? undefined : ppid;
  } catch {
    return undefined;
  }
}

function getAncestorPids(pid: number): Set<number> {
  const ancestors = new Set<number>();
  let current = pid;
  while (current > 1) {
    const ppid = readPpid(current);
    if (ppid === undefined || ppid <= 1 || ancestors.has(ppid)) break;
    ancestors.add(ppid);
    current = ppid;
  }
  return ancestors;
}

export class TerminalMapper implements vscode.Disposable {
  private readonly sessionTerminals = new Map<string, vscode.Terminal>();
  private readonly disposables: vscode.Disposable[] = [];
  private readonly _onDidMatch = new vscode.EventEmitter<void>();
  readonly onDidMatch: vscode.Event<void> = this._onDidMatch.event;
  private ownSessionCache = new Map<number, boolean>();
  private readonly log: vscode.LogOutputChannel;

  constructor(private readonly discovery: SessionDiscovery, log: vscode.LogOutputChannel) {
    this.log = log;
    this.log.debug('TerminalMapper initialized');
    this.disposables.push(
      vscode.window.onDidOpenTerminal(() => {
        this.ownSessionCache.clear();
        void this.matchAll();
      }),
      vscode.window.onDidCloseTerminal(t => {
        for (const [id, mapped] of this.sessionTerminals) {
          if (mapped === t) {
            this.sessionTerminals.delete(id);
            const session = this.discovery.getSession(id);
            if (session) session.terminal = undefined;
          }
        }
        this.ownSessionCache.clear();
        void this.matchAll();
      }),
      this._onDidMatch,
    );

    void this.matchAll();
  }

  isOwnSessionSync(pid: number): boolean {
    return this.ownSessionCache.get(pid) ?? false;
  }

  async matchAll(): Promise<void> {
    const termPids = new Map<number, vscode.Terminal>();
    await Promise.all(vscode.window.terminals.map(async t => {
      const pid = await t.processId;
      if (pid !== undefined) termPids.set(pid, t);
    }));

    let changed = false;
    let matchedCount = 0;

    for (const [id, session] of this.discovery.getSessions()) {
      const ancestors = getAncestorPids(session.pid);
      let matched = false;

      for (const [termPid, terminal] of termPids) {
        if (ancestors.has(termPid) || session.pid === termPid) {
          this.ownSessionCache.set(session.pid, true);
          if (!this.sessionTerminals.has(id) || this.sessionTerminals.get(id) !== terminal) {
            this.sessionTerminals.set(id, terminal);
            session.terminal = terminal;
            changed = true;
          }
          matched = true;
          matchedCount++;
          break;
        }
      }

      if (!matched) {
        this.ownSessionCache.set(session.pid, false);
      }
    }

    const sessions = this.discovery.getSessions();
    this.log.debug(`matchAll: ${termPids.size} terminals, ${sessions.size} sessions, ${matchedCount} matched`);

    if (changed) this._onDidMatch.fire();
  }

  async focusSession(sessionId: string): Promise<void> {
    const cached = this.sessionTerminals.get(sessionId);
    if (cached) {
      this.log.debug(`focusSession: cached hit ${sessionId.slice(0, 8)}`);
      cached.show();
      return;
    }

    const session = this.discovery.getSession(sessionId);
    if (!session) {
      this.log.debug(`focusSession: session not found ${sessionId.slice(0, 8)}`);
      return;
    }

    const ancestors = getAncestorPids(session.pid);

    for (const t of vscode.window.terminals) {
      const pid = await t.processId;
      if (pid !== undefined && (ancestors.has(pid) || session.pid === pid)) {
        this.sessionTerminals.set(sessionId, t);
        session.terminal = t;
        this.log.debug(`focusSession: matched via ancestry ${sessionId.slice(0, 8)}`);
        t.show();
        return;
      }
    }
    this.log.debug(`focusSession: no terminal found ${sessionId.slice(0, 8)}`);
  }

  dispose(): void {
    for (const d of this.disposables) d.dispose();
    this.sessionTerminals.clear();
    this.ownSessionCache.clear();
  }
}
