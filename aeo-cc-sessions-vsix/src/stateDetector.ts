import * as fs from 'node:fs';
import * as path from 'node:path';
import type * as vscode from 'vscode';
import type { SessionState } from './types.js';

export interface Log {
  trace(message: string, ...args: any[]): void;
  debug(message: string, ...args: any[]): void;
  info(message: string, ...args: any[]): void;
  warn(message: string, ...args: any[]): void;
  error(error: string | Error, ...args: any[]): void;
}

type StateChangeCallback = (sessionId: string, state: SessionState, toolName?: string, toolDetail?: string) => void;

const IGNORED_TYPES = new Set([
  'file-history-snapshot', 'last-prompt', 'custom-title', 'agent-name',
]);

const SYSTEM_STATE_MAP: Record<string, SessionState> = {
  turn_duration: 'idle',
  compact_boundary: 'compact',
  microcompact_boundary: 'compact',
  api_error: 'error',
};

type JsonRecord = Record<string, unknown>;
type ContentBlock = { type?: string; name?: string; input?: JsonRecord; [k: string]: unknown };

const PROMPT_TOOLS = new Set(['AskUserQuestion', 'request_user_input', 'ExitPlanMode']);
const PROSE_APPROVAL_RE = /\b(?:want me to|do you want me to|would you like me to|should i|shall i)\b.*\b(?:apply|patch|edit|update|fix|change|modify)\b/i;
const MUTATING_APPROVAL_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Bash']);

// ---------------------------------------------------------------------------
// Record handlers (progress is batched in doRead, not dispatched here)
// ---------------------------------------------------------------------------

type HandlerContext = {
  prefix: string;
  permissionMode?: string;
  emit: (state: SessionState, toolName?: string, toolDetail?: string) => void;
  log: Log;
};

function recTs(record: JsonRecord): string {
  const t = record['timestamp'] as string | undefined;
  return t ? t.slice(11, 23) : '?';
}

function resolveMessage(record: JsonRecord): JsonRecord | undefined {
  return (record['message'] ?? (record['data'] as JsonRecord | undefined)?.['message']) as JsonRecord | undefined;
}

function resolveContent(record: JsonRecord): unknown {
  return resolveMessage(record)?.['content'];
}

function handleSystem(record: JsonRecord, ctx: HandlerContext): void {
  const subtype = record['subtype'] as string ?? 'unknown';
  const state = SYSTEM_STATE_MAP[subtype];
  if (state) {
    ctx.log.info(`${ctx.prefix} system/${subtype} → ${state}  (rec=${recTs(record)})`);
    ctx.emit(state);
  } else {
    ctx.log.debug(`${ctx.prefix} system/${subtype} (no state change)  (rec=${recTs(record)})`);
  }
}

function handleQueueOp(record: JsonRecord, ctx: HandlerContext): void {
  const op = (record['operation'] ?? record['action'] ?? '?') as string;
  ctx.log.debug(`${ctx.prefix} queue-op/${op}  (rec=${recTs(record)})`);
}

function handleProgress(record: JsonRecord, ctx: HandlerContext): void {
  const data = record['data'] as JsonRecord | undefined;
  const nested = data?.['message'] as JsonRecord | undefined;
  const nestedType = nested?.['type'];
  const nestedMessage = nested?.['message'] as JsonRecord | undefined;

  if ((nestedType === 'assistant' || nestedType === 'user') && nestedMessage) {
    const synthetic: JsonRecord = {
      timestamp: record['timestamp'],
      message: nestedMessage,
    };
    if (nestedType === 'assistant') {
      handleAssistant(synthetic, ctx);
      return;
    }
    handleUser(synthetic, ctx);
    return;
  }

  const progressType = data?.['type'] as string | undefined;
  const hookEvent = data?.['hookEvent'] as string | undefined;
  ctx.log.debug(`${ctx.prefix} progress/${progressType ?? hookEvent ?? '?'}  (rec=${recTs(record)})`);
}

function handleUser(record: JsonRecord, ctx: HandlerContext): void {
  if (typeof record['permissionMode'] === 'string') {
    ctx.permissionMode = record['permissionMode'] as string;
  }

  const content = resolveContent(record);

  if (Array.isArray(content)) {
    const types = (content as ContentBlock[]).map(b => b.type ?? '?');
    const hasToolResult = types.includes('tool_result');
    if (hasToolResult) {
      ctx.log.info(`${ctx.prefix} user/tool_result → thinking  blocks=[${types}]  (rec=${recTs(record)})`);
      ctx.emit('thinking');
      return;
    }
    ctx.log.info(`${ctx.prefix} user/array → thinking  blocks=[${types}]  (rec=${recTs(record)})`);
    ctx.emit('thinking');
    return;
  }

  if (typeof content === 'string') {
    ctx.log.info(`${ctx.prefix} user/text → thinking  len=${content.length}  (rec=${recTs(record)})`);
    ctx.emit('thinking');
  } else {
    ctx.log.debug(`${ctx.prefix} user/unknown  content_type=${typeof content}  (rec=${recTs(record)})`);
  }
}

function handleAssistant(record: JsonRecord, ctx: HandlerContext): void {
  const message = resolveMessage(record);
  const content = message?.['content'];
  const stopReason = message?.['stop_reason'] as string | undefined;

  if (!Array.isArray(content)) {
    ctx.log.debug(`${ctx.prefix} assistant/no-content  stop=${stopReason ?? '?'}  (rec=${recTs(record)})`);
    return;
  }

  const blocks = content as ContentBlock[];
  const toolUses = blocks.filter(b => b.type === 'tool_use');
  const blockTypes = blocks.map(b => b.type ?? '?');

  if (toolUses.length > 0) {
    const names = toolUses.map(t => t.name as string);
    const first = toolUses.find(t => PROMPT_TOOLS.has(t.name as string)) ?? toolUses[0];
    const toolName = first.name as string;
    const input = first.input as JsonRecord | undefined;
    const detail = extractToolDetail(toolName, input);
    const parallel = toolUses.length > 1 ? ` +${toolUses.length - 1} parallel` : '';
    ctx.log.info(`${ctx.prefix} assistant/tool → tool  tools=[${names}]${parallel}  stop=${stopReason ?? '?'}  blocks=[${blockTypes}]  (rec=${recTs(record)})`);
    if (PROMPT_TOOLS.has(toolName)) {
      ctx.emit('prompt', toolName, detail);
      return;
    }
    if (shouldPromptForToolApproval(toolName, input, ctx.permissionMode)) {
      ctx.emit('prompt', toolName, describeApprovalPrompt(toolName, input, detail));
      return;
    }
    ctx.emit('tool', toolName, detail);
  } else if (stopReason === 'end_turn') {
    const promptDetail = extractAssistantApprovalPromptDetail(blocks);
    if (promptDetail) {
      ctx.log.info(`${ctx.prefix} assistant/text → prompt  stop=end_turn  blocks=[${blockTypes}]  (rec=${recTs(record)})`);
      ctx.emit('prompt', undefined, promptDetail);
      return;
    }
    ctx.log.info(`${ctx.prefix} assistant/text → idle  stop=end_turn  blocks=[${blockTypes}]  (rec=${recTs(record)})`);
    ctx.emit('idle');
  } else {
    ctx.log.info(`${ctx.prefix} assistant/text → thinking  stop=${stopReason ?? '?'}  blocks=[${blockTypes}]  (rec=${recTs(record)})`);
    ctx.emit('thinking');
  }
}

// ---------------------------------------------------------------------------
// Handler dispatch table
// ---------------------------------------------------------------------------

const HANDLERS: Record<string, (record: JsonRecord, ctx: HandlerContext) => void> = {
  system: handleSystem,
  progress: handleProgress,
  'queue-operation': handleQueueOp,
  user: handleUser,
  assistant: handleAssistant,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function extractToolDetail(name: string, input: JsonRecord | undefined): string | undefined {
  if (!input) return undefined;
  switch (name) {
    case 'Read':
    case 'Edit':
    case 'Write':
      return typeof input['file_path'] === 'string' ? path.basename(input['file_path']) : undefined;
    case 'Bash':
      return typeof input['command'] === 'string' ? input['command'] as string : undefined;
    case 'Grep':
    case 'Glob':
      return typeof input['pattern'] === 'string' ? input['pattern'] as string : undefined;
    case 'Agent': {
      if (typeof input['description'] === 'string' && input['description'].trim().length > 0) {
        return input['description'] as string;
      }
      if (typeof input['name'] === 'string' && input['name'].trim().length > 0) {
        return input['name'] as string;
      }
      return typeof input['prompt'] === 'string' ? input['prompt'] as string : undefined;
    }
    case 'AskUserQuestion':
    case 'request_user_input': {
      const questions = input['questions'];
      if (Array.isArray(questions) && questions.length > 0) {
        const first = questions[0] as JsonRecord;
        if (typeof first['header'] === 'string' && (first['header'] as string).trim().length > 0) {
          return first['header'] as string;
        }
        if (typeof first['question'] === 'string') {
          return first['question'] as string;
        }
      }
      return undefined;
    }
    case 'ExitPlanMode': {
      const plan = input['plan'];
      if (typeof plan !== 'string') return undefined;
      const firstMeaningfulLine = plan
        .split('\n')
        .map(line => line.trim())
        .find(line => line.length > 0);
      if (!firstMeaningfulLine) return undefined;
      return firstMeaningfulLine.replace(/^#+\s*/, '');
    }
    case 'WebSearch':
      return typeof input['query'] === 'string' ? input['query'] as string : undefined;
    default:
      return undefined;
  }
}

function describeApprovalPrompt(toolName: string, input: JsonRecord | undefined, toolDetail?: string): string {
  if (toolName === 'Bash' && typeof input?.['description'] === 'string' && (input['description'] as string).trim().length > 0) {
    return `Approve bash: ${input['description'] as string}`;
  }
  if (toolDetail) {
    return `Approve ${toolName.toLowerCase()}: ${toolDetail}`;
  }
  return `Approve ${toolName.toLowerCase()}`;
}

function shouldPromptForToolApproval(
  toolName: string,
  input: JsonRecord | undefined,
  permissionMode?: string,
): boolean {
  if (permissionMode === 'default' && MUTATING_APPROVAL_TOOLS.has(toolName)) {
    return true;
  }

  if (toolName === 'Bash' && typeof input?.['command'] === 'string') {
    return hasQuotedNewlineCommentRisk(input['command'] as string);
  }

  return false;
}

function hasQuotedNewlineCommentRisk(command: string): boolean {
  const lines = command.split('\n');
  if (lines.length < 2) return false;
  const firstLine = lines[0];
  if (!/["']\s*$/.test(firstLine)) return false;
  return lines.slice(1).some(line => line.trimStart().startsWith('#'));
}

function extractAssistantApprovalPromptDetail(blocks: ContentBlock[]): string | undefined {
  const rawLines = blocks
    .filter(block => block.type === 'text')
    .flatMap(block => typeof block.text === 'string' ? block.text.split('\n') : []);

  const textLines: string[] = [];
  let inFence = false;
  for (const rawLine of rawLines) {
    const line = rawLine.trim();
    if (line.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || line.length === 0) continue;
    textLines.push(line);
  }

  const tail = textLines.slice(-4);
  for (let i = tail.length - 1; i >= 0; i -= 1) {
    const line = tail[i];
    if (PROSE_APPROVAL_RE.test(line)) {
      return line;
    }
  }

  return undefined;
}

// ---------------------------------------------------------------------------
// StateDetector
// ---------------------------------------------------------------------------

export class StateDetector implements vscode.Disposable {
  private filePath: string;
  private readonly resolvePath: () => string;
  private byteOffset = 0;
  private lastSize = 0;
  private lastIno = 0;
  private fsWatcher: fs.FSWatcher | undefined;
  private pollInterval: ReturnType<typeof setInterval> | undefined;
  private windowStateDisposable: vscode.Disposable | undefined;
  private disposed = false;
  private reading = false;
  private watchRetryLogged = false;
  private readonly pollIntervalMs: number;

  private readonly ctx: HandlerContext;

  constructor(
    resolvePath: () => string,
    sessionId: string,
    pid: number,
    pollIntervalMs: number,
    onStateChange: StateChangeCallback,
    log: Log,
  ) {
    this.resolvePath = resolvePath;
    this.filePath = resolvePath();
    this.pollIntervalMs = pollIntervalMs;

    const project = path.basename(path.dirname(this.filePath));
    const prefix = `[${project}] ${sessionId.slice(0, 8)} pid=${pid}`;

    this.ctx = {
      prefix,
      emit: (state, toolName, toolDetail) => onStateChange(sessionId, state, toolName, toolDetail),
      log,
    };
  }

  private switchTo(newPath: string): void {
    this.ctx.log.info(`${this.ctx.prefix} path_switch  ${path.basename(this.filePath)} → ${path.basename(newPath)}`);
    this.filePath = newPath;
    this.byteOffset = 0;
    this.lastSize = 0;
    this.lastIno = 0;
    if (this.fsWatcher) { this.fsWatcher.close(); this.fsWatcher = undefined; }
    this.watchRetryLogged = false;
  }

  private checkPathChange(): void {
    const newPath = this.resolvePath();
    if (newPath !== this.filePath) {
      this.switchTo(newPath);
    }
  }

  start(): void {
    this.ctx.log.info(`${this.ctx.prefix} started  path=${this.filePath}`);
    this.tryWatch();

    this.pollInterval = setInterval(() => {
      if (!this.disposed) {
        this.checkPathChange();
        this.tryWatch();
        void this.readNewData();
      }
    }, this.pollIntervalMs);

    const vscode = require('vscode') as typeof import('vscode');
    this.windowStateDisposable = vscode.window.onDidChangeWindowState((e: { focused: boolean }) => {
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
      this.watchRetryLogged = false;
      this.ctx.log.info(`${this.ctx.prefix} watch_ok`);
    } catch {
      if (!this.watchRetryLogged) {
        this.ctx.log.debug(`${this.ctx.prefix} watch_pending (file not ready)`);
        this.watchRetryLogged = true;
      }
    }
  }

  private async readNewData(): Promise<void> {
    if (this.disposed || this.reading) return;
    this.reading = true;
    try {
      await this.doRead();
    } finally {
      this.reading = false;
    }
  }

  private async doRead(): Promise<void> {
    if (this.disposed) return;

    let stat: fs.Stats;
    try {
      stat = await fs.promises.stat(this.filePath);
    } catch {
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
    this.ctx.log.debug(`${this.ctx.prefix} read ${raw.length}B, ${lines.length} lines`);

    let progressCount = 0;
    for (const line of lines) {
      if (this.disposed) return;
      if (this.processLine(line)) progressCount++;
    }
    if (progressCount > 0) {
      this.ctx.log.debug(`${this.ctx.prefix} progress: ${progressCount} records`);
    }
  }

  /** Returns true if the line was a progress record (batched by doRead). */
  private processLine(line: string): boolean {
    // Fast path: skip JSON.parse for progress records (~43% of JSONL)
    if (line.startsWith('{"type":"progress"')) return true;

    let record: JsonRecord;
    try {
      record = JSON.parse(line);
    } catch {
      this.ctx.log.warn(`${this.ctx.prefix} PARSE_ERROR  line=${line.slice(0, 80)}`);
      return false;
    }

    const type = record['type'] as string | undefined;
    if (!type) {
      this.ctx.log.warn(`${this.ctx.prefix} NO_TYPE  keys=${Object.keys(record).join(',')}`);
      return false;
    }

    if (type === 'progress') return true;

    if (IGNORED_TYPES.has(type)) {
      this.ctx.log.debug(`${this.ctx.prefix} ignored/${type}  (rec=${recTs(record)})`);
      return false;
    }

    const handler = HANDLERS[type];
    if (handler) {
      handler(record, this.ctx);
    } else {
      this.ctx.log.warn(`${this.ctx.prefix} UNHANDLED type=${type}  (rec=${recTs(record)})`);
    }
    return false;
  }

  dispose(): void {
    this.ctx.log.info(`${this.ctx.prefix} disposed`);
    this.disposed = true;
    if (this.fsWatcher) { this.fsWatcher.close(); this.fsWatcher = undefined; }
    if (this.pollInterval) { clearInterval(this.pollInterval); this.pollInterval = undefined; }
    if (this.windowStateDisposable) { this.windowStateDisposable.dispose(); this.windowStateDisposable = undefined; }
  }
}
