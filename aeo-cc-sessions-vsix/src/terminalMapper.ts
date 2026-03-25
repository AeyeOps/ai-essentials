import * as vscode from 'vscode';
import type { SessionDiscovery } from './sessionDiscovery.js';
import { readProcStat } from './proc.js';

function getAncestorPids(pid: number): Set<number> {
  const ancestors = new Set<number>();
  let current = pid;
  while (current > 1) {
    const ppid = readProcStat(current)?.ppid;
    if (ppid === undefined || ppid <= 1 || ancestors.has(ppid)) break;
    ancestors.add(ppid);
    current = ppid;
  }
  return ancestors;
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

  private trace(
    traceId: string | undefined,
    stage: string,
    fields: Record<string, string | number | boolean | undefined>,
  ): void {
    logFocusTrace(this.log, traceId, stage, fields);
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

  getActiveSessionId(): string | undefined {
    const active = vscode.window.activeTerminal;
    if (!active) return undefined;
    for (const [id, terminal] of this.sessionTerminals) {
      if (terminal === active) return id;
    }
    return undefined;
  }

  getActiveTerminalSessionIds(): string[] {
    const active = vscode.window.activeTerminal;
    if (!active) return [];

    const sessionIds: string[] = [];
    for (const [id, terminal] of this.sessionTerminals) {
      if (terminal === active) {
        sessionIds.push(id);
      }
    }
    return sessionIds;
  }

  getActiveSessionIds(): Set<string> {
    const active = vscode.window.activeTerminal;
    if (!active) return new Set();

    const ids = new Set<string>();
    for (const [id, terminal] of this.sessionTerminals) {
      if (terminal === active) {
        ids.add(id);
      }
    }
    return ids;
  }

  private async findTerminalForSession(sessionId: string, traceId?: string): Promise<vscode.Terminal | undefined> {
    const cached = this.sessionTerminals.get(sessionId);
    if (cached) {
      this.trace(traceId, 'mapper.lookup.cache-hit', {
        sessionId: sessionId.slice(0, 8),
        terminalName: cached.name,
      });
      this.log.debug(`findTerminalForSession: cache hit ${sessionId.slice(0, 8)}`);
      return cached;
    }

    const session = this.discovery.getSession(sessionId);
    if (!session) {
      this.trace(traceId, 'mapper.lookup.session-missing', {
        sessionId: sessionId.slice(0, 8),
      });
      this.log.debug(`findTerminalForSession: session missing ${sessionId.slice(0, 8)}`);
      return undefined;
    }

    if (session.terminal) {
      this.sessionTerminals.set(sessionId, session.terminal);
      this.trace(traceId, 'mapper.lookup.session-terminal-hit', {
        sessionId: sessionId.slice(0, 8),
        terminalName: session.terminal.name,
      });
      this.log.debug(`findTerminalForSession: session.terminal hit ${sessionId.slice(0, 8)}`);
      return session.terminal;
    }

    const ancestors = getAncestorPids(session.pid);
    const lookupStartedAt = Date.now();
    this.trace(traceId, 'mapper.lookup.scan-start', {
      sessionId: sessionId.slice(0, 8),
      sessionPid: session.pid,
      ancestorCount: ancestors.size,
      terminalCount: vscode.window.terminals.length,
    });
    const pidResolutionStartedAt = Date.now();
    const terminalInfos = await Promise.all(vscode.window.terminals.map(async terminal => ({
      terminal,
      pid: await terminal.processId,
    })));
    this.trace(traceId, 'mapper.lookup.scan-pids-resolved', {
      sessionId: sessionId.slice(0, 8),
      pidResolutionMs: Date.now() - pidResolutionStartedAt,
      terminalCount: terminalInfos.length,
    });

    for (const { terminal, pid } of terminalInfos) {
      if (pid !== undefined && (ancestors.has(pid) || session.pid === pid)) {
        this.sessionTerminals.set(sessionId, terminal);
        session.terminal = terminal;
        this.trace(traceId, 'mapper.lookup.scan-match', {
          sessionId: sessionId.slice(0, 8),
          terminalName: terminal.name,
          terminalPid: pid,
          lookupMs: Date.now() - lookupStartedAt,
        });
        this.log.debug(`findTerminalForSession: scan matched ${sessionId.slice(0, 8)} in ${Date.now() - lookupStartedAt}ms`);
        return terminal;
      }
    }

    this.trace(traceId, 'mapper.lookup.scan-miss', {
      sessionId: sessionId.slice(0, 8),
      lookupMs: Date.now() - lookupStartedAt,
      terminalCount: terminalInfos.length,
    });
    this.log.debug(`findTerminalForSession: scan miss ${sessionId.slice(0, 8)} in ${Date.now() - lookupStartedAt}ms`);
    return undefined;
  }

  getSessionGroupIds(sessionId: string): Set<string> {
    const terminal = this.sessionTerminals.get(sessionId) ?? this.discovery.getSession(sessionId)?.terminal;
    if (!terminal) return new Set();

    const ids = new Set<string>();
    for (const [id, mapped] of this.sessionTerminals) {
      if (mapped === terminal) {
        ids.add(id);
      }
    }
    return ids;
  }

  async focusSession(sessionId: string, traceId?: string): Promise<{ status: 'missing-session' | 'missing-terminal' | 'already-active' | 'show-called'; targetTerminalName?: string }> {
    const startedAt = Date.now();
    const session = this.discovery.getSession(sessionId);
    if (!session) {
      this.trace(traceId, 'mapper.focus.session-missing', {
        sessionId: sessionId.slice(0, 8),
      });
      this.log.debug(`focusSession: session not found ${sessionId.slice(0, 8)}`);
      return { status: 'missing-session' };
    }

    this.trace(traceId, 'mapper.focus.start', {
      sessionId: sessionId.slice(0, 8),
      processKey: session.processKey,
      sessionPid: session.pid,
      activeTerminalName: vscode.window.activeTerminal?.name,
      terminalCount: vscode.window.terminals.length,
    });

    const terminal = await this.findTerminalForSession(sessionId, traceId);
    if (!terminal) {
      this.trace(traceId, 'mapper.focus.terminal-missing', {
        sessionId: sessionId.slice(0, 8),
        totalMs: Date.now() - startedAt,
      });
      this.log.debug(`focusSession: no terminal found ${sessionId.slice(0, 8)}`);
      return { status: 'missing-terminal' };
    }

    const alreadyActive = vscode.window.activeTerminal === terminal;
    this.trace(traceId, 'mapper.focus.before-show', {
      sessionId: sessionId.slice(0, 8),
      alreadyActive,
      activeTerminalName: vscode.window.activeTerminal?.name,
      targetTerminalName: terminal.name,
      totalMs: Date.now() - startedAt,
    });
    if (alreadyActive) {
      return { status: 'already-active', targetTerminalName: terminal.name };
    }

    const showStartedAt = Date.now();
    terminal.show();
    this.trace(traceId, 'mapper.focus.after-show', {
      sessionId: sessionId.slice(0, 8),
      targetTerminalName: terminal.name,
      showCallMs: Date.now() - showStartedAt,
      totalMs: Date.now() - startedAt,
    });
    this.log.debug(`focusSession: resolved ${sessionId.slice(0, 8)} in ${Date.now() - startedAt}ms, show() returned in ${Date.now() - showStartedAt}ms`);
    return { status: 'show-called', targetTerminalName: terminal.name };
  }

  async closeSession(sessionId: string): Promise<boolean> {
    const terminal = await this.findTerminalForSession(sessionId);
    if (!terminal) {
      this.log.debug(`closeSession: no terminal found ${sessionId.slice(0, 8)}`);
      return false;
    }

    this.log.debug(`closeSession: resolved ${sessionId.slice(0, 8)}`);
    terminal.dispose();
    return true;
  }

  dispose(): void {
    for (const d of this.disposables) d.dispose();
    this.sessionTerminals.clear();
    this.ownSessionCache.clear();
  }
}
