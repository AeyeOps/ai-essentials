import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import type * as vscode from 'vscode';
import {
  getTranscriptPath,
  resolveContinueFromCmdline,
  resolveConversationFromCmdline,
  resolveTaskFromFd,
} from './sessionDiscovery.js';

interface HistoryRow {
  display: string;
  project: string;
  sessionId: string;
  timestamp: number;
}

interface TranscriptMeta {
  agentName?: string;
  customTitle?: string;
  firstPromptId?: string;
  lastPromptId?: string;
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

export interface TranscriptSessionMetadata {
  customTitle?: string;
  firstPromptId?: string;
  lastPromptId?: string;
  path: string;
  sessionId: string;
  slug?: string;
  startKind?: string;
  startTsMs?: number;
}

export interface TranscriptLineageItem {
  sessionId: string;
  path?: string;
  customTitle?: string;
  agentName?: string;
  slug?: string;
  startKind?: string;
  linkSource: 'current' | 'transcript-link' | 'resolver-edge';
}

export interface SessionPresentationMeta {
  agentName?: string;
  customTitle?: string;
  path: string;
  sessionId: string;
  slug?: string;
  startKind?: string;
}

const HISTORY_PATH = path.join(os.homedir(), '.claude', 'history.jsonl');
const CONTINUE_GRACE_MS = 5_000;
const HISTORY_EDGE_PRE_WINDOW_MS = 5_000;
const MAX_START_PARSE_BYTES = 256 * 1024;
const MAX_END_PARSE_BYTES = 64 * 1024;
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

function readSuffix(filePath: string): string {
  let fd: number | undefined;
  try {
    fd = fs.openSync(filePath, 'r');
    const stat = fs.fstatSync(fd);
    const size = Math.min(stat.size, MAX_END_PARSE_BYTES);
    const start = Math.max(0, stat.size - size);
    const buffer = Buffer.alloc(size);
    fs.readSync(fd, buffer, 0, size, start);
    return buffer.toString('utf-8');
  } catch {
    return '';
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

function hydratePresentationMetaFromFullTranscript(filePath: string, meta: TranscriptMeta): void {
  if (meta.customTitle && meta.agentName && meta.slug) return;

  for (const line of readJsonlRows(filePath)) {
    try {
      const record = JSON.parse(line) as Record<string, unknown>;
      if (!meta.slug && typeof record.slug === 'string') {
        meta.slug = record.slug;
      }
      if (record.type === 'agent-name' && typeof record.agentName === 'string') {
        meta.agentName = record.agentName;
      }
      if (record.type === 'custom-title' && typeof record.customTitle === 'string') {
        meta.customTitle = record.customTitle;
      }
    } catch {
      continue;
    }
  }
}

function extractRenamedSessionLabel(content: string): string | undefined {
  const stdoutMatch = /Session renamed to:\s*([^<\n]+)/u.exec(content);
  if (stdoutMatch?.[1]) {
    return stdoutMatch[1].trim();
  }

  const argsMatch = /<command-name>\/rename<\/command-name>[\s\S]*?<command-args>([^<]+)<\/command-args>/u.exec(content);
  if (argsMatch?.[1]) {
    return argsMatch[1].trim();
  }

  return undefined;
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
  const prefixLines = prefix.split('\n').filter(Boolean).slice(0, 20);
  for (const line of prefixLines) {
    try {
      const record = JSON.parse(line) as Record<string, unknown>;

      if (!meta.slug && typeof record.slug === 'string') {
        meta.slug = record.slug;
      }

      if (!meta.agentName && record.type === 'agent-name' && typeof record.agentName === 'string') {
        meta.agentName = record.agentName;
      }

      if (!meta.customTitle && record.type === 'custom-title' && typeof record.customTitle === 'string') {
        meta.customTitle = record.customTitle;
      }

      if (record.type === 'system' && record.subtype === 'local_command' && typeof record.content === 'string') {
        const renamed = extractRenamedSessionLabel(record.content);
        if (renamed) {
          meta.customTitle = renamed;
          meta.agentName = renamed;
        }
      }

      if (!meta.startKind && record.type === 'progress') {
        const data = record.data as Record<string, unknown> | undefined;
        if (data?.hookEvent === 'SessionStart' && typeof data.hookName === 'string') {
          meta.startKind = data.hookName.split(':').at(-1);
          meta.startTsMs = parseIsoMs(record.timestamp);
        }
      }

      if (record.type === 'user') {
        if (!meta.firstPromptId && typeof record.promptId === 'string') {
          meta.firstPromptId = record.promptId;
        }

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

  const suffix = readSuffix(filePath);
  const suffixLines = suffix.split('\n').filter(Boolean);
  for (const line of suffixLines) {
    try {
      const record = JSON.parse(line) as Record<string, unknown>;
      if (record.type === 'agent-name' && typeof record.agentName === 'string') {
        meta.agentName = record.agentName;
      }
      if (record.type === 'custom-title' && typeof record.customTitle === 'string') {
        meta.customTitle = record.customTitle;
      }
      if (record.type === 'system' && record.subtype === 'local_command' && typeof record.content === 'string') {
        const renamed = extractRenamedSessionLabel(record.content);
        if (renamed) {
          meta.customTitle = renamed;
          meta.agentName = renamed;
        }
      }
    } catch {
      continue;
    }
  }

  const tailWindow = suffixLines.slice(Math.max(0, suffixLines.length - 200));
  for (const line of tailWindow) {
    try {
      const record = JSON.parse(line) as Record<string, unknown>;
      if (record.type === 'user' && typeof record.promptId === 'string') {
        meta.lastPromptId = record.promptId;
      }
    } catch {
      continue;
    }
  }

  if (!meta.customTitle || !meta.agentName) {
    hydratePresentationMetaFromFullTranscript(filePath, meta);
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

type HandoffKind = 'clear' | 'compact';

function parseHandoffKind(display: string): HandoffKind | undefined {
  const normalized = display.trim().toLowerCase();
  if (normalized === '/clear') return 'clear';
  if (normalized === '/compact') return 'compact';
  return undefined;
}

function isHandoffStart(meta: TranscriptMeta, kind: HandoffKind): boolean {
  if (kind === 'clear') {
    return meta.startKind === 'clear' || meta.startsWithClearCommand;
  }
  return meta.startKind === 'compact';
}

function metaSortTs(meta: TranscriptMeta): number {
  return Math.max(meta.startTsMs ?? Number.NEGATIVE_INFINITY, meta.mtimeMs);
}

export class TranscriptResolver {
  private readonly log: vscode.LogOutputChannel;
  private readonly historyRows = new Map<string, HistoryRow[]>();
  private historyMtimeMs = -1;
  private readonly lastDecisionByPid = new Map<number, string>();
  private readonly projects = new Map<string, ProjectCache>();

  constructor(log: vscode.LogOutputChannel) {
    this.log = log;
  }

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

  private buildEdges(cwd: string, metas: Map<string, TranscriptMeta>): Map<string, Set<string>> {
    const edges = new Map<string, Set<string>>();

    for (const meta of metas.values()) {
      if (meta.previousTranscriptId) {
        addEdge(edges, meta.previousTranscriptId, meta.sessionId);
      }
    }

    const metasByLastPrompt = new Map<string, TranscriptMeta[]>();
    for (const meta of metas.values()) {
      if (!meta.lastPromptId) continue;
      const bucket = metasByLastPrompt.get(meta.lastPromptId) ?? [];
      bucket.push(meta);
      metasByLastPrompt.set(meta.lastPromptId, bucket);
    }
    for (const bucket of metasByLastPrompt.values()) {
      bucket.sort((a, b) => (a.startTsMs ?? a.mtimeMs) - (b.startTsMs ?? b.mtimeMs));
    }

    for (const meta of metas.values()) {
      const isHandoffDescendant = meta.startKind === 'clear' || meta.startKind === 'compact' || meta.startsWithClearCommand;
      if (!isHandoffDescendant || !meta.firstPromptId) continue;

      const candidates = metasByLastPrompt.get(meta.firstPromptId) ?? [];
      const metaStart = metaSortTs(meta);
      let bestCandidate: TranscriptMeta | undefined;
      for (const candidate of candidates) {
        if (candidate.sessionId === meta.sessionId) continue;
        const candidateStart = metaSortTs(candidate);
        if (candidateStart >= metaStart) continue;
        if (!bestCandidate || candidateStart > metaSortTs(bestCandidate)) {
          bestCandidate = candidate;
        }
      }

      if (bestCandidate) {
        addEdge(edges, bestCandidate.sessionId, meta.sessionId);
      }
    }

    this.loadHistoryRows();
    const rows = this.historyRows.get(cwd) ?? [];
    for (const row of rows) {
      const handoffKind = parseHandoffKind(row.display);
      if (!handoffKind) continue;

      let bestCandidate:
        | { deltaMs: number; absDeltaMs: number; meta: TranscriptMeta; prefersAfter: boolean }
        | undefined;
      for (const meta of metas.values()) {
        if (meta.sessionId === row.sessionId) continue;
        if (!isHandoffStart(meta, handoffKind)) continue;

        const startTs = meta.startTsMs ?? meta.mtimeMs;
        const deltaMs = startTs - row.timestamp;
        if (deltaMs < -HISTORY_EDGE_PRE_WINDOW_MS || deltaMs > HISTORY_EDGE_WINDOW_MS) continue;

        const candidate = {
          deltaMs,
          absDeltaMs: Math.abs(deltaMs),
          meta,
          prefersAfter: deltaMs >= 0,
        };

        if (
          !bestCandidate
          || Number(candidate.prefersAfter) > Number(bestCandidate.prefersAfter)
          || (
            candidate.prefersAfter === bestCandidate.prefersAfter
            && (
              candidate.absDeltaMs < bestCandidate.absDeltaMs
              || (
                candidate.absDeltaMs === bestCandidate.absDeltaMs
                && metaSortTs(candidate.meta) < metaSortTs(bestCandidate.meta)
              )
            )
          )
        ) {
          bestCandidate = candidate;
        }
      }

      if (bestCandidate) {
        addEdge(edges, row.sessionId, bestCandidate.meta.sessionId);
      }
    }

    return edges;
  }

  private findContinueAnchor(
    metas: Map<string, TranscriptMeta>,
    processStartedAt?: number,
  ): string | undefined {
    const cutoffMs = typeof processStartedAt === 'number'
      ? processStartedAt + CONTINUE_GRACE_MS
      : Number.POSITIVE_INFINITY;

    let best: TranscriptMeta | undefined;
    for (const meta of metas.values()) {
      const anchorTs = meta.startTsMs ?? meta.mtimeMs;
      if (anchorTs > cutoffMs) continue;
      if (!best || anchorTs > (best.startTsMs ?? best.mtimeMs)) {
        best = meta;
      }
    }
    return best?.sessionId;
  }

  private traceDecision(
    pid: number,
    details: {
      anchors: string[];
      chosenSessionId: string;
      continueMode: boolean;
      continueSessionId?: string;
      reachableIds: string[];
      source: string;
    },
  ): void {
    const summary = JSON.stringify(details);
    if (this.lastDecisionByPid.get(pid) === summary) return;
    this.lastDecisionByPid.set(pid, summary);
    this.log.debug(`resolver pid=${pid} ${summary}`);
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

  getLineageStack(
    cwd: string,
    currentSessionId?: string,
    currentTranscriptPath?: string,
  ): TranscriptLineageItem[] {
    const projectDir = transcriptProjectDir(cwd);
    const project = this.loadProject(projectDir);
    const transcriptSessionId = currentTranscriptPath ? path.basename(currentTranscriptPath, '.jsonl') : undefined;
    const startId = [currentSessionId, transcriptSessionId]
      .find((value): value is string => typeof value === 'string' && project.bySessionId.has(value));

    if (!startId) {
      return [];
    }

    const edges = this.buildEdges(cwd, project.bySessionId);
    const reverseParents = new Map<string, Set<string>>();
    for (const [parentId, childIds] of edges) {
      for (const childId of childIds) {
        const parents = reverseParents.get(childId) ?? new Set<string>();
        parents.add(parentId);
        reverseParents.set(childId, parents);
      }
    }

    const stack: TranscriptLineageItem[] = [];
    const seen = new Set<string>();
    let currentId: string | undefined = startId;
    let linkSource: TranscriptLineageItem['linkSource'] = 'current';

    while (currentId && !seen.has(currentId)) {
      seen.add(currentId);
      const meta = project.bySessionId.get(currentId);
      if (!meta) {
        stack.push({ sessionId: currentId, linkSource });
        break;
      }

      stack.push({
        agentName: meta.agentName,
        customTitle: meta.customTitle,
        sessionId: meta.sessionId,
        path: meta.path,
        slug: meta.slug,
        startKind: meta.startKind,
        linkSource,
      });

      if (meta.previousTranscriptId && project.bySessionId.has(meta.previousTranscriptId)) {
        currentId = meta.previousTranscriptId;
        linkSource = 'transcript-link';
        continue;
      }

      const parentIds = [...(reverseParents.get(meta.sessionId) ?? [])]
        .filter(parentId => parentId !== meta.sessionId && !seen.has(parentId));
      if (parentIds.length === 0) {
        break;
      }

      parentIds.sort((a, b) => {
        const aMeta = project.bySessionId.get(a);
        const bMeta = project.bySessionId.get(b);
        return (bMeta ? metaSortTs(bMeta) : 0) - (aMeta ? metaSortTs(aMeta) : 0);
      });
      currentId = parentIds[0];
      linkSource = 'resolver-edge';
    }

    return stack;
  }

  getSessionMetadata(
    cwd: string,
    currentSessionId?: string,
    currentTranscriptPath?: string,
  ): TranscriptSessionMetadata | undefined {
    const projectDir = transcriptProjectDir(cwd);
    const project = this.loadProject(projectDir);
    const transcriptSessionId = currentTranscriptPath ? path.basename(currentTranscriptPath, '.jsonl') : undefined;
    const startId = [currentSessionId, transcriptSessionId]
      .find((value): value is string => typeof value === 'string' && project.bySessionId.has(value));

    if (!startId) {
      return undefined;
    }

    const meta = project.bySessionId.get(startId);
    if (!meta) {
      return undefined;
    }

    return {
      customTitle: meta.customTitle,
      firstPromptId: meta.firstPromptId,
      lastPromptId: meta.lastPromptId,
      path: meta.path,
      sessionId: meta.sessionId,
      slug: meta.slug,
      startKind: meta.startKind,
      startTsMs: meta.startTsMs,
    };
  }

  getSessionPresentation(
    cwd: string,
    currentSessionId?: string,
    transcriptPath?: string,
  ): SessionPresentationMeta | undefined {
    const project = this.loadProject(transcriptProjectDir(cwd));
    const candidateIds = [
      currentSessionId,
      transcriptPath ? path.basename(transcriptPath, '.jsonl') : undefined,
    ].filter((value, index, values): value is string => (
      typeof value === 'string'
      && value.length > 0
      && values.indexOf(value) === index
    ));

    for (const sessionId of candidateIds) {
      const meta = project.bySessionId.get(sessionId);
      if (!meta) continue;
      return {
        agentName: meta.agentName,
        customTitle: meta.customTitle,
        path: meta.path,
        sessionId: meta.sessionId,
        slug: meta.slug,
        startKind: meta.startKind,
      };
    }

    return undefined;
  }

  resolve(
    pid: number,
    cwd: string,
    registrySessionId: string,
    previousResolvedSessionId?: string,
    processStartedAt?: number,
  ): TranscriptResolution {
    const projectDir = transcriptProjectDir(cwd);
    const project = this.loadProject(projectDir);

    const continueMode = resolveContinueFromCmdline(pid);
    const resumeSessionId = resolveConversationFromCmdline(pid);
    const taskSessionId = resolveTaskFromFd(pid);
    const continueSessionId = continueMode
      ? this.findContinueAnchor(project.bySessionId, processStartedAt)
      : undefined;

    const anchors = [
      previousResolvedSessionId,
      taskSessionId,
      resumeSessionId,
      continueSessionId,
      registrySessionId,
    ].filter((value): value is string => typeof value === 'string' && value.length > 0);

    const edges = this.buildEdges(cwd, project.bySessionId);
    const reachableIds = this.walkReachable(anchors, edges);

    let best: { meta: TranscriptMeta; score: number; source: string } | undefined;
    for (const sessionId of reachableIds) {
      const meta = project.bySessionId.get(sessionId);
      if (!meta) continue;

      const score = Math.max(meta.mtimeMs, meta.startTsMs ?? Number.NEGATIVE_INFINITY);
      const source = continueMode && continueSessionId && reachableIds.has(continueSessionId)
        ? 'cmdline-continue-chain'
        : taskSessionId && reachableIds.has(taskSessionId)
          ? 'task-chain'
          : resumeSessionId && reachableIds.has(resumeSessionId)
            ? 'cmdline-resume-chain'
            : previousResolvedSessionId && reachableIds.has(previousResolvedSessionId)
              ? 'resolved-chain'
              : 'transcript-chain';
      if (!best || score > best.score) {
        best = { meta, score, source };
      }
    }

    if (best) {
      this.traceDecision(pid, {
        anchors,
        chosenSessionId: best.meta.sessionId,
        continueMode,
        continueSessionId,
        reachableIds: [...reachableIds].sort(),
        source: best.source,
      });
      return {
        path: best.meta.path,
        sessionId: best.meta.sessionId,
        source: best.source,
      };
    }

    const fallbackSessionId = taskSessionId ?? resumeSessionId ?? continueSessionId ?? registrySessionId;
    const fallbackPath = getTranscriptPath(cwd, fallbackSessionId);
    const fallbackSource = fallbackSessionId === taskSessionId
      ? 'task-fd'
      : fallbackSessionId === resumeSessionId
        ? 'cmdline-resume'
        : fallbackSessionId === continueSessionId
          ? 'cmdline-continue'
          : 'registry';

    this.traceDecision(pid, {
      anchors,
      chosenSessionId: fallbackSessionId,
      continueMode,
      continueSessionId,
      reachableIds: [],
      source: fallbackSource,
    });
    return {
      path: project.bySessionId.get(fallbackSessionId)?.path ?? fallbackPath,
      sessionId: fallbackSessionId,
      source: fallbackSource,
    };
  }
}
