import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import type * as vscode from 'vscode';
import {
  getTranscriptPath,
  resolveConversationFromCmdline,
  resolveTaskFromFd,
} from './sessionDiscovery.js';

interface HistoryRow {
  display: string;
  project: string;
  sessionId: string;
  timestamp: number;
}

interface StatuslineEntry {
  atMs: number;
  sessionId: string;
  sessionName?: string;
  transcriptPath: string;
  cwd: string;
}

interface TranscriptMeta {
  customTitle?: string;
  path: string;
  mtimeMs: number;
  sessionId: string;
  slug?: string;
  startKind?: string;
  startTsMs?: number;
  startsWithClearCommand: boolean;
  previousTranscriptId?: string;
}

interface ProjectCache {
  bySessionId: Map<string, TranscriptMeta>;
  fileStats: Map<string, number>;
}

export interface TranscriptResolution {
  path: string;
  sessionId: string;
  source: string;
}

const HISTORY_PATH = path.join(os.homedir(), '.claude', 'history.jsonl');
const STATUSLINE_PATH = path.join(os.homedir(), '.claude', 'statusline-activity.jsonl');
const MAX_START_PARSE_BYTES = 256 * 1024;
const HISTORY_EDGE_WINDOW_MS = 60_000;

const PREVIOUS_TRANSCRIPT_RE = new RegExp(
  `${escapeRegExp(path.join(os.homedir(), '.claude', 'projects'))}\\/[^/]+\\/([0-9a-f-]{36})\\.jsonl`,
  'i',
);

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseIsoMs(value: unknown): number | undefined {
  if (typeof value !== 'string') return undefined;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? undefined : ms;
}

function readJsonlRows(filePath: string): string[] {
  try {
    return fs.readFileSync(filePath, 'utf-8')
      .split('\n')
      .filter(Boolean);
  } catch {
    return [];
  }
}

function extractContentText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';

  const parts: string[] = [];
  for (const item of content) {
    if (!item || typeof item !== 'object') continue;

    const maybeText = (item as { text?: unknown }).text;
    if (typeof maybeText === 'string') {
      parts.push(maybeText);
      continue;
    }

    const maybeContent = (item as { content?: unknown }).content;
    if (typeof maybeContent === 'string') {
      parts.push(maybeContent);
    }
  }
  return parts.join('\n');
}

function readPrefix(filePath: string): string {
  let fd: number | undefined;
  try {
    fd = fs.openSync(filePath, 'r');
    const stat = fs.fstatSync(fd);
    const size = Math.min(stat.size, MAX_START_PARSE_BYTES);
    const buffer = Buffer.alloc(size);
    fs.readSync(fd, buffer, 0, size, 0);
    return buffer.toString('utf-8');
  } catch {
    return '';
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

function parseTranscriptMeta(filePath: string, mtimeMs: number): TranscriptMeta {
  const sessionId = path.basename(filePath, '.jsonl');
  const meta: TranscriptMeta = {
    path: filePath,
    mtimeMs,
    sessionId,
    startsWithClearCommand: false,
  };

  const prefix = readPrefix(filePath);
  if (!prefix) return meta;

  const lines = prefix.split('\n').filter(Boolean).slice(0, 20);
  for (const line of lines) {
    try {
      const record = JSON.parse(line) as Record<string, unknown>;

      if (!meta.slug && typeof record.slug === 'string') {
        meta.slug = record.slug;
      }

      if (!meta.customTitle && record.type === 'custom-title' && typeof record.customTitle === 'string') {
        meta.customTitle = record.customTitle;
      }

      if (!meta.startKind && record.type === 'progress') {
        const data = record.data as Record<string, unknown> | undefined;
        if (data?.hookEvent === 'SessionStart' && typeof data.hookName === 'string') {
          meta.startKind = data.hookName.split(':').at(-1);
          meta.startTsMs = parseIsoMs(record.timestamp);
        }
      }

      if (record.type === 'user') {
        const message = record.message as Record<string, unknown> | undefined;
        const contentText = extractContentText(message?.content);

        if (!meta.previousTranscriptId) {
          const match = PREVIOUS_TRANSCRIPT_RE.exec(contentText);
          if (match && match[1] !== sessionId) {
            meta.previousTranscriptId = match[1];
          }
        }

        if (
          contentText.includes('<command-name>/clear</command-name>')
          || contentText.trim() === '/clear'
        ) {
          meta.startsWithClearCommand = true;
        }
      }
    } catch {
      continue;
    }
  }

  return meta;
}

function transcriptProjectDir(cwd: string): string {
  const encoded = cwd.replace(/\//g, '-');
  return path.join(os.homedir(), '.claude', 'projects', encoded);
}

function addEdge(edges: Map<string, Set<string>>, fromId: string, toId: string): void {
  if (!fromId || !toId || fromId === toId) return;
  const current = edges.get(fromId) ?? new Set<string>();
  current.add(toId);
  edges.set(fromId, current);
}

export class TranscriptResolver {
  private readonly historyRows = new Map<string, HistoryRow[]>();
  private historyMtimeMs = -1;
  private readonly projects = new Map<string, ProjectCache>();
  private readonly statuslineBySession = new Map<string, StatuslineEntry>();
  private statuslineMtimeMs = -1;

  constructor(_log: vscode.LogOutputChannel) {}

  private loadProject(projectDir: string): ProjectCache {
    const cached = this.projects.get(projectDir) ?? {
      bySessionId: new Map<string, TranscriptMeta>(),
      fileStats: new Map<string, number>(),
    };

    let fileNames: string[];
    try {
      fileNames = fs.readdirSync(projectDir).filter(name => name.endsWith('.jsonl'));
    } catch {
      fileNames = [];
    }

    const seen = new Set<string>();
    for (const name of fileNames) {
      const filePath = path.join(projectDir, name);
      let stat: fs.Stats;
      try {
        stat = fs.statSync(filePath);
      } catch {
        continue;
      }

      seen.add(filePath);
      const previousMtime = cached.fileStats.get(filePath);
      if (previousMtime !== stat.mtimeMs) {
        cached.bySessionId.set(path.basename(name, '.jsonl'), parseTranscriptMeta(filePath, stat.mtimeMs));
        cached.fileStats.set(filePath, stat.mtimeMs);
      }
    }

    for (const filePath of [...cached.fileStats.keys()]) {
      if (seen.has(filePath)) continue;
      cached.fileStats.delete(filePath);
      cached.bySessionId.delete(path.basename(filePath, '.jsonl'));
    }

    this.projects.set(projectDir, cached);
    return cached;
  }

  private loadHistoryRows(): void {
    let stat: fs.Stats;
    try {
      stat = fs.statSync(HISTORY_PATH);
    } catch {
      this.historyRows.clear();
      this.historyMtimeMs = -1;
      return;
    }

    if (stat.mtimeMs === this.historyMtimeMs) return;

    const perProject = new Map<string, HistoryRow[]>();
    for (const line of readJsonlRows(HISTORY_PATH)) {
      try {
        const row = JSON.parse(line) as Record<string, unknown>;
        if (
          typeof row.project !== 'string'
          || typeof row.sessionId !== 'string'
          || typeof row.timestamp !== 'number'
          || typeof row.display !== 'string'
        ) {
          continue;
        }

        const projectRows = perProject.get(row.project) ?? [];
        projectRows.push({
          display: row.display,
          project: row.project,
          sessionId: row.sessionId,
          timestamp: row.timestamp,
        });
        perProject.set(row.project, projectRows);
      } catch {
        continue;
      }
    }

    this.historyRows.clear();
    for (const [project, rows] of perProject) {
      rows.sort((a, b) => a.timestamp - b.timestamp);
      this.historyRows.set(project, rows);
    }
    this.historyMtimeMs = stat.mtimeMs;
  }

  private loadStatuslineEntries(): void {
    let stat: fs.Stats;
    try {
      stat = fs.statSync(STATUSLINE_PATH);
    } catch {
      this.statuslineBySession.clear();
      this.statuslineMtimeMs = -1;
      return;
    }

    if (stat.mtimeMs === this.statuslineMtimeMs) return;

    this.statuslineBySession.clear();
    for (const line of readJsonlRows(STATUSLINE_PATH)) {
      try {
        const row = JSON.parse(line) as Record<string, unknown>;
        if (
          typeof row.session_id !== 'string'
          || typeof row.transcript_path !== 'string'
          || typeof row.cwd !== 'string'
          || typeof row.meta_ts !== 'string'
        ) {
          continue;
        }

        const atMs = parseIsoMs(row.meta_ts);
        if (atMs === undefined) continue;

        const current = this.statuslineBySession.get(row.session_id);
        if (current && current.atMs >= atMs) continue;

        this.statuslineBySession.set(row.session_id, {
          atMs,
          cwd: row.cwd,
          sessionId: row.session_id,
          sessionName: typeof row.session_name === 'string' ? row.session_name : undefined,
          transcriptPath: row.transcript_path,
        });
      } catch {
        continue;
      }
    }
    this.statuslineMtimeMs = stat.mtimeMs;
  }

  private buildEdges(cwd: string, metas: Map<string, TranscriptMeta>): Map<string, Set<string>> {
    const edges = new Map<string, Set<string>>();

    for (const meta of metas.values()) {
      if (meta.previousTranscriptId) {
        addEdge(edges, meta.previousTranscriptId, meta.sessionId);
      }
    }

    this.loadHistoryRows();
    const rows = this.historyRows.get(cwd) ?? [];
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index];
      const normalized = row.display.trim().toLowerCase();
      if (normalized !== '/clear' && normalized !== '/compact') continue;

      let bestCandidate: { delta: number; sessionId: string } | undefined;
      for (let nextIndex = index + 1; nextIndex < rows.length; nextIndex++) {
        const next = rows[nextIndex];
        if (next.timestamp - row.timestamp > HISTORY_EDGE_WINDOW_MS) break;
        if (next.sessionId === row.sessionId) continue;

        const target = metas.get(next.sessionId);
        if (!target?.startTsMs) continue;
        if (normalized === '/clear' && !target.startsWithClearCommand) continue;

        const startDelta = Math.abs(target.startTsMs - row.timestamp);
        if (startDelta > HISTORY_EDGE_WINDOW_MS) continue;

        if (!bestCandidate || startDelta < bestCandidate.delta) {
          bestCandidate = { delta: startDelta, sessionId: next.sessionId };
        }
      }

      if (bestCandidate) {
        addEdge(edges, row.sessionId, bestCandidate.sessionId);
      }
    }

    return edges;
  }

  private walkReachable(anchors: string[], edges: Map<string, Set<string>>): Set<string> {
    const seen = new Set<string>();
    const queue = [...anchors];

    while (queue.length > 0) {
      const sessionId = queue.shift();
      if (!sessionId || seen.has(sessionId)) continue;
      seen.add(sessionId);

      for (const childId of edges.get(sessionId) ?? []) {
        queue.push(childId);
      }
    }

    return seen;
  }

  resolve(
    pid: number,
    cwd: string,
    registrySessionId: string,
    previousResolvedSessionId?: string,
  ): TranscriptResolution {
    const projectDir = transcriptProjectDir(cwd);
    const project = this.loadProject(projectDir);
    this.loadStatuslineEntries();

    const resumeSessionId = resolveConversationFromCmdline(pid);
    const taskSessionId = resolveTaskFromFd(pid);

    const anchors = [
      previousResolvedSessionId,
      taskSessionId,
      resumeSessionId,
      registrySessionId,
    ].filter((value): value is string => typeof value === 'string' && value.length > 0);

    const edges = this.buildEdges(cwd, project.bySessionId);
    const reachableIds = this.walkReachable(anchors, edges);

    let best: { meta: TranscriptMeta; score: number; source: string } | undefined;
    for (const sessionId of reachableIds) {
      const meta = project.bySessionId.get(sessionId);
      if (!meta) continue;

      const activity = this.statuslineBySession.get(sessionId);
      const score = activity && activity.cwd === cwd
        ? 1_000_000_000_000_000 + activity.atMs
        : meta.mtimeMs;

      const source = activity && activity.cwd === cwd ? 'statusline-chain' : 'transcript-chain';
      if (!best || score > best.score) {
        best = { meta, score, source };
      }
    }

    if (best) {
      return {
        path: best.meta.path,
        sessionId: best.meta.sessionId,
        source: best.source,
      };
    }

    const fallbackSessionId = taskSessionId ?? resumeSessionId ?? registrySessionId;
    const fallbackPath = getTranscriptPath(cwd, fallbackSessionId);
    return {
      path: project.bySessionId.get(fallbackSessionId)?.path ?? fallbackPath,
      sessionId: fallbackSessionId,
      source: fallbackSessionId === taskSessionId
        ? 'task-fd'
        : fallbackSessionId === resumeSessionId
          ? 'cmdline-resume'
          : 'registry',
    };
  }
}
