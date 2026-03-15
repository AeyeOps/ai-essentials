import * as vscode from 'vscode';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { SessionState } from './types.js';

type StateChangeCallback = (sessionId: string, state: SessionState, toolName?: string, toolDetail?: string) => void;

export class StateDetector implements vscode.Disposable {
  private readonly filePath: string;
  private readonly sessionId: string;
  private readonly onStateChange: StateChangeCallback;
  private readonly log: vscode.OutputChannel | undefined;
  private byteOffset = 0;
  private lastSize = 0;
  private lastIno = 0;
  private fsWatcher: fs.FSWatcher | undefined;
  private idleTimer: ReturnType<typeof setTimeout> | undefined;
  private pollInterval: ReturnType<typeof setInterval> | undefined;
  private windowStateDisposable: vscode.Disposable | undefined;
  private disposed = false;
  private typeCounts: Record<string, number> | undefined;
  private noMsgCounts: Record<string, number> | undefined;

  constructor(filePath: string, sessionId: string, onStateChange: StateChangeCallback, log?: vscode.OutputChannel) {
    this.filePath = filePath;
    this.sessionId = sessionId;
    this.onStateChange = onStateChange;
    this.log = log;
  }

  start(): void {
    this.tryWatch();

    this.pollInterval = setInterval(() => {
      if (!this.disposed) {
        this.tryWatch();
        void this.readNewData();
      }
    }, 3_000);

    this.windowStateDisposable = vscode.window.onDidChangeWindowState(e => {
      if (!this.disposed && e.focused) void this.readNewData();
    });

    void this.readNewData();
  }

  private tryWatch(): void {
    if (this.fsWatcher || this.disposed) return;
    try {
      this.fsWatcher = fs.watch(this.filePath, () => {
        if (!this.disposed) void this.readNewData();
      });
      this.fsWatcher.on('error', () => {
        this.fsWatcher?.close();
        this.fsWatcher = undefined;
      });
    } catch {
      // file may not exist yet
    }
  }

  private async readNewData(): Promise<void> {
    if (this.disposed) return;

    let stat: fs.Stats;
    try {
      stat = await fs.promises.stat(this.filePath);
    } catch (e) {
      return;
    }

    this.tryWatch();

    if (stat.ino !== this.lastIno && this.lastIno !== 0) {
      this.byteOffset = 0;
    } else if (stat.size < this.lastSize) {
      this.byteOffset = 0;
    }
    this.lastIno = stat.ino;
    this.lastSize = stat.size;

    if (stat.size <= this.byteOffset) return;

    const chunks: Buffer[] = [];
    try {
      await new Promise<void>((resolve, reject) => {
        const stream = fs.createReadStream(this.filePath, {
          start: this.byteOffset,
          end: stat.size - 1,
        });
        stream.on('data', (chunk: Buffer | string) => chunks.push(Buffer.from(chunk)));
        stream.on('end', resolve);
        stream.on('error', reject);
      });
    } catch {
      return;
    }

    this.byteOffset = stat.size;
    if (this.disposed) return;

    const raw = Buffer.concat(chunks).toString('utf-8');
    const lines = raw.split('\n').filter(l => l.length > 0);
    this.log?.appendLine(`readNewData: read ${raw.length}B, ${lines.length} lines`);

    let stateChanges = 0;
    for (const line of lines) {
      if (this.disposed) return;
      const before = stateChanges;
      this.processLine(line);
      if (stateChanges === before) {
        // count via side-effect of processLine calling onStateChange
      }
    }
    if (this.typeCounts && Object.keys(this.typeCounts).length > 0) {
      this.log?.appendLine(`readNewData: types=${JSON.stringify(this.typeCounts)} noMsg=${JSON.stringify(this.noMsgCounts ?? {})}`);
      this.typeCounts = undefined;
      this.noMsgCounts = undefined;
    }
    this.log?.appendLine(`readNewData: done processing`);
  }

  private processLine(line: string): void {
    let record: Record<string, unknown>;
    try {
      record = JSON.parse(line);
    } catch {
      return;
    }

    const type = record['type'] as string | undefined;
    if (!type) return;
    if (type === 'progress' || type === 'system' || type === 'file-history-snapshot') return;

    const message = (record['message'] ?? (record['data'] as Record<string, unknown> | undefined)?.['message']) as Record<string, unknown> | undefined;
    const content = message?.['content'];

    if (!this.typeCounts) this.typeCounts = {};
    this.typeCounts[type] = (this.typeCounts[type] ?? 0) + 1;
    if (!message) {
      if (!this.noMsgCounts) this.noMsgCounts = {};
      this.noMsgCounts[type] = (this.noMsgCounts[type] ?? 0) + 1;
    }

    if (type === 'user') {
      if (Array.isArray(content)) {
        const hasToolResult = content.some(
          (b: Record<string, unknown>) => b['type'] === 'tool_result'
        );
        if (hasToolResult) return;
      }
      if (typeof content === 'string') {
        this.resetIdleTimer();
        this.onStateChange(this.sessionId, 'thinking');
      }
      return;
    }

    if (type === 'assistant') {
      if (!Array.isArray(content)) return;

      const toolUseBlock = (content as Record<string, unknown>[]).find(
        (b: Record<string, unknown>) => b['type'] === 'tool_use'
      );

      if (toolUseBlock) {
        const toolName = toolUseBlock['name'] as string;
        const input = toolUseBlock['input'] as Record<string, unknown> | undefined;
        const toolDetail = this.extractToolDetail(toolName, input);
        if (this.idleTimer) { clearTimeout(this.idleTimer); this.idleTimer = undefined; }
        this.onStateChange(this.sessionId, 'tool', toolName, toolDetail);
      } else {
        this.resetIdleTimer();
        this.onStateChange(this.sessionId, 'thinking');
      }
    }
  }

  private extractToolDetail(name: string, input: Record<string, unknown> | undefined): string | undefined {
    if (!input) return undefined;

    switch (name) {
      case 'Read':
      case 'Edit':
      case 'Write':
        return typeof input['file_path'] === 'string'
          ? path.basename(input['file_path'])
          : undefined;
      case 'Bash':
        return typeof input['command'] === 'string'
          ? input['command'].slice(0, 40)
          : undefined;
      case 'Grep':
        return typeof input['pattern'] === 'string'
          ? input['pattern']
          : undefined;
      case 'Glob':
        return typeof input['pattern'] === 'string'
          ? input['pattern']
          : undefined;
      case 'Agent':
        return typeof input['prompt'] === 'string'
          ? input['prompt'].slice(0, 30)
          : undefined;
      case 'WebSearch':
        return typeof input['query'] === 'string'
          ? input['query']
          : undefined;
      default:
        return undefined;
    }
  }

  private resetIdleTimer(): void {
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      if (!this.disposed) {
        this.onStateChange(this.sessionId, 'idle');
      }
    }, 3_000);
  }

  dispose(): void {
    this.disposed = true;
    if (this.fsWatcher) {
      this.fsWatcher.close();
      this.fsWatcher = undefined;
    }
    if (this.idleTimer) {
      clearTimeout(this.idleTimer);
      this.idleTimer = undefined;
    }
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = undefined;
    }
    if (this.windowStateDisposable) {
      this.windowStateDisposable.dispose();
      this.windowStateDisposable = undefined;
    }
  }
}
