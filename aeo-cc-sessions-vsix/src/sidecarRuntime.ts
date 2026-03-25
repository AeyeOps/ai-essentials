import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
import * as vscode from 'vscode';
import type { SessionInfo, SessionState, SidecarHealth } from './types.js';

const execFileAsync = promisify(execFile);

export const SIDECAR_PLUGIN_NAME = 'aeo-vsc-cc-sessions-sidecar';
export const SIDECAR_MARKETPLACE_NAME = 'aeo-skill-marketplace';
export const SIDECAR_MARKETPLACE_SOURCE = 'https://github.com/AeyeOps/aeo-skill-marketplace.git';
export const MIN_SIDECAR_VERSION = '0.3.0';
export const SIDECAR_ROOT = path.join(os.homedir(), '.claude', 'aeo-vsc-cc-sessions');
const THINKING_STATE_STALE_MS = 60 * 60_000;
const COMPACTING_STATE_STALE_MS = 30 * 60_000;
const STARTUP_GRACE_MS = 10_000;
const EVENT_SYNC_TOLERANCE_MS = 60_000;
const INSTALLED_PLUGIN_LIST_CACHE_MS = 30_000;

type ListedPluginEntry = {
  id?: string;
  scope?: string;
  enabled?: boolean;
  installPath?: string;
  version?: string;
  installedAt?: string;
  lastUpdated?: string;
  projectPath?: string;
};

export interface SidecarInstallCandidate {
  key: string;
  scope: string;
  installPath?: string;
  version?: string;
  accepted: boolean;
  reason: string;
  source: 'cli' | 'file-fallback';
}

export interface SidecarInstall {
  key: string;
  installPath?: string;
  scope: string;
  version: string;
}

export interface SidecarState {
  writer_version?: string;
  updated_at?: string;
  process_key?: string;
  current_session_id?: string;
  current_transcript_path?: string;
  cwd?: string;
  state?: string;
  needs_user_attention?: boolean;
  attention_kind?: string | null;
  permission_mode?: string | null;
  tool_name?: string | null;
  tool_summary?: string | null;
  notification_type?: string | null;
  ended_reason?: string | null;
  compact?: {
    pending?: boolean;
    trigger?: string | null;
    summary_path?: string | null;
    summary_excerpt?: string | null;
  };
  subagents?: {
    active_count?: number;
    last_started_type?: string | null;
    last_started_at?: string | null;
    last_stopped_type?: string | null;
  };
  lineage?: {
    start_source?: string | null;
    previous_session_id?: string | null;
    previous_transcript_path?: string | null;
  };
  last_event?: {
    hook_event_name?: string;
    ts?: string;
  };
}

export interface SidecarAssessment {
  health: SidecarHealth;
  message: string;
  state?: SidecarState;
}

type CommandResult = {
  step: string;
  command: string;
  code: number;
  stdout: string;
  stderr: string;
};

let installedPluginListCache:
  | { expiresAt: number; entries: ListedPluginEntry[]; source: 'cli' }
  | undefined;

function parseIso(ts: string | undefined): number | undefined {
  if (!ts) return undefined;
  const parsed = Date.parse(ts);
  return Number.isNaN(parsed) ? undefined : parsed;
}

function compareSemver(a: string, b: string): number {
  const aParts = a.split('.').map(part => parseInt(part, 10));
  const bParts = b.split('.').map(part => parseInt(part, 10));
  const length = Math.max(aParts.length, bParts.length);
  for (let i = 0; i < length; i += 1) {
    const av = aParts[i] ?? 0;
    const bv = bParts[i] ?? 0;
    if (Number.isNaN(av) || Number.isNaN(bv)) {
      return a.localeCompare(b);
    }
    if (av !== bv) return av - bv;
  }
  return 0;
}

function sessionProcessDir(session: SessionInfo): string {
  return path.join(SIDECAR_ROOT, 'processes', `${session.pid}-${session.pidStartTicks}`);
}

function readJson<T>(filePath: string): T | undefined {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8')) as T;
  } catch {
    return undefined;
  }
}

function statePathForSession(session: SessionInfo): string {
  return path.join(sessionProcessDir(session), 'state.json');
}

function eventsPathForSession(session: SessionInfo): string {
  return path.join(sessionProcessDir(session), 'events.jsonl');
}

function normalizeCommandResult(result: CommandResult, okPatterns: RegExp[]): CommandResult {
  if (result.code === 0) return result;
  const haystack = `${result.stdout}\n${result.stderr}`;
  if (okPatterns.some(pattern => pattern.test(haystack))) {
    return { ...result, code: 0 };
  }
  return result;
}

function formatCommand(args: string[]): string {
  return ['claude', ...args]
    .map(part => /[\s"]/u.test(part) ? JSON.stringify(part) : part)
    .join(' ');
}

function readInstalledPluginsFromCli(): ListedPluginEntry[] | undefined {
  try {
    const stdout = execFileSync('claude', ['plugins', 'list', '--json'], {
      cwd: os.homedir(),
      env: process.env,
      encoding: 'utf8',
      maxBuffer: 1024 * 1024,
    });
    const parsed = JSON.parse(stdout);
    if (!Array.isArray(parsed)) return undefined;
    return parsed.filter((entry): entry is ListedPluginEntry => typeof entry === 'object' && entry !== null);
  } catch {
    return undefined;
  }
}

function getInstalledPluginEntries(): { entries: ListedPluginEntry[]; source: 'cli' } {
  const now = Date.now();
  if (installedPluginListCache && installedPluginListCache.expiresAt > now) {
    return {
      entries: installedPluginListCache.entries,
      source: installedPluginListCache.source,
    };
  }

  installedPluginListCache = {
    expiresAt: now + INSTALLED_PLUGIN_LIST_CACHE_MS,
    entries: readInstalledPluginsFromCli() ?? [],
    source: 'cli',
  };
  return {
    entries: installedPluginListCache.entries,
    source: 'cli',
  };
}

function invalidateInstalledPluginEntriesCache(): void {
  installedPluginListCache = undefined;
}

export function listInstalledSidecarCandidates(): SidecarInstallCandidate[] {
  const { entries, source } = getInstalledPluginEntries();
  return entries
    .filter(entry => typeof entry.id === 'string' && entry.id.startsWith(`${SIDECAR_PLUGIN_NAME}@`))
    .map(entry => {
      const key = entry.id!;
      const scope = entry.scope ?? 'unknown';
      const enabled = entry.enabled ?? true;
      const installPath = typeof entry.installPath === 'string' ? entry.installPath : undefined;
      if (scope !== 'user') {
        return {
          key,
          scope,
          installPath,
          version: entry.version,
          accepted: false,
          reason: `ignored-${scope}-scope`,
          source,
        };
      }
      if (!enabled) {
        return {
          key,
          scope,
          installPath,
          version: entry.version,
          accepted: false,
          reason: 'ignored-disabled-install',
          source,
        };
      }
      return {
        key,
        scope,
        installPath,
        version: entry.version,
        accepted: true,
        reason: 'user-scope-candidate',
        source,
      };
    });
}

export function loadInstalledSidecar(): SidecarAssessment & { install?: SidecarInstall } {
  const { entries } = getInstalledPluginEntries();
  if (entries.length === 0) {
    return {
      health: 'missing-plugin',
      message: 'Claude runtime installation metadata is missing.',
    };
  }

  const candidates = listInstalledSidecarCandidates();
  const matches = candidates
    .filter(candidate => candidate.accepted)
    .map(candidate => ({
      key: candidate.key,
      entry: {
        scope: candidate.scope,
        installPath: candidate.installPath,
        version: candidate.version,
      },
    }));

  if (matches.length === 0) {
    if (candidates.some(candidate => candidate.reason === 'ignored-disabled-install')) {
      return {
        health: 'disabled',
        message: 'Claude runtime is installed but disabled for this user profile.',
      };
    }
    return {
      health: 'missing-plugin',
      message: 'Claude runtime is not installed for this user profile.',
    };
  }

  if (matches.length > 1) {
    return {
      health: 'plugin-conflict',
      message: 'Multiple Claude runtime installs were detected for this user profile.',
    };
  }

  const match = matches[0];
  const runtimeVersion = match.entry.version?.trim();
  if (runtimeVersion && compareSemver(runtimeVersion, MIN_SIDECAR_VERSION) < 0) {
    return {
      health: 'invalid',
      message: `The installed Claude runtime version ${runtimeVersion} is below the minimum supported version ${MIN_SIDECAR_VERSION}.`,
    };
  }

  return {
    health: 'healthy',
    message: 'Claude runtime is installed and available.',
    install: {
      key: match.key,
      installPath: match.entry.installPath,
      scope: match.entry.scope ?? 'user',
      version: runtimeVersion ?? 'unknown',
    },
  };
}

function isStateStale(state: SidecarState): boolean {
  const updatedAt = parseIso(state.updated_at);
  if (!updatedAt || !state.state) return false;
  const ageMs = Date.now() - updatedAt;

  switch (state.state) {
    case 'thinking':
      return ageMs > THINKING_STATE_STALE_MS;
    case 'tool_pending':
      // Long-running tools can legitimately run for hours.
      return false;
    case 'compacting':
      return ageMs > COMPACTING_STATE_STALE_MS;
    case 'prompt':
      // Waiting for input is not inherently stale.
      return false;
    default:
      return false;
  }
}

export function assessSidecarForSession(
  session: SessionInfo,
  install: SidecarAssessment & { install?: SidecarInstall },
): SidecarAssessment {
  if (install.health !== 'healthy') {
    const withinGrace = Date.now() - session.observedAt < STARTUP_GRACE_MS;
    const startupEligible = install.health === 'missing-state' || install.health === 'stale';
    if (startupEligible && withinGrace) {
      return {
        health: 'starting',
        message: 'Waiting for runtime startup grace window.',
      };
    }
    return install;
  }

  if (!fs.existsSync(SIDECAR_ROOT)) {
    const withinGrace = Date.now() - session.observedAt < STARTUP_GRACE_MS;
    if (withinGrace) {
      return {
        health: 'starting',
        message: 'Waiting for runtime state to appear.',
      };
    }
    return {
      health: 'missing-state',
      message: 'Runtime state root is missing.',
    };
  }

  const state = readJson<SidecarState>(statePathForSession(session));
  if (!state) {
    const withinGrace = Date.now() - session.observedAt < STARTUP_GRACE_MS;
    if (withinGrace) {
      return {
        health: 'starting',
        message: 'Waiting for the first runtime state file.',
      };
    }
    return {
      health: 'missing-state',
      message: 'Runtime state is missing for this session.',
    };
  }

  if (state.process_key && state.process_key !== session.processKey) {
    return {
      health: 'invalid',
      message: 'Runtime process identity mismatch.',
    };
  }

  let eventsStat: fs.Stats | undefined;
  try {
    eventsStat = fs.statSync(eventsPathForSession(session));
  } catch {
    eventsStat = undefined;
  }
  if (!eventsStat || eventsStat.size <= 0) {
    return {
      health: 'invalid',
      message: 'Runtime events are missing for this session.',
      state,
    };
  }

  const stateUpdatedAt = parseIso(state.updated_at);
  if (stateUpdatedAt !== undefined && Math.abs(eventsStat.mtimeMs - stateUpdatedAt) > EVENT_SYNC_TOLERANCE_MS) {
    return {
      health: 'stale',
      message: 'Runtime events are out of sync for this session.',
      state,
    };
  }

  if (isStateStale(state)) {
    return {
      health: 'stale',
      message: `Runtime state is stale while the session is ${state.state}.`,
      state,
    };
  }

  return {
    health: 'healthy',
    message: install.message,
    state,
  };
}

function mapSidecarState(state: SidecarState): { state: SessionState; toolName?: string; toolDetail?: string } {
  const toolName = state.tool_name ?? undefined;
  const toolDetail = state.tool_summary ?? undefined;

  switch (state.state) {
    case 'idle':
      return { state: 'idle' };
    case 'thinking':
      return { state: 'thinking' };
    case 'tool_pending':
      return { state: 'tool', toolName, toolDetail };
    case 'prompt':
      if (state.attention_kind === 'permission') {
        return { state: 'permission', toolName, toolDetail };
      }
      return { state: 'prompt', toolName, toolDetail };
    case 'compacting':
      return { state: 'compact' };
    case 'error':
      return { state: 'error', toolDetail: toolDetail ?? 'Runtime reported an error' };
    case 'ended':
      return { state: 'exited' };
    default:
      return { state: 'error', toolDetail: `Unknown runtime state: ${state.state ?? 'undefined'}` };
  }
}

export function applySidecarAssessment(session: SessionInfo, assessment: SidecarAssessment): boolean {
  const previous = {
    state: session.state,
    toolName: session.toolName,
    toolDetail: session.toolDetail,
    activeSubagentCount: session.activeSubagentCount,
    sidecarHealth: session.sidecarHealth,
    sidecarMessage: session.sidecarMessage,
    transcriptSessionId: session.transcriptSessionId,
    transcriptPath: session.transcriptPath,
    sessionId: session.sessionId,
    startSource: session.startSource,
    previousTranscriptSessionId: session.previousTranscriptSessionId,
    previousTranscriptPath: session.previousTranscriptPath,
    cwd: session.cwd,
  };

  session.sidecarHealth = assessment.health;
  session.sidecarMessage = assessment.message;
  session.sidecarUpdatedAt = parseIso(assessment.state?.updated_at);
  session.activeSubagentCount = undefined;

  if (assessment.health === 'healthy' && assessment.state) {
    const mapped = mapSidecarState(assessment.state);
    session.state = mapped.state;
    session.toolName = mapped.toolName;
    session.toolDetail = mapped.toolDetail;
    session.activeSubagentCount = assessment.state.subagents?.active_count;
    session.stateChangedAt = session.sidecarUpdatedAt ?? Date.now();
    if (assessment.state.current_session_id) {
      session.sessionId = assessment.state.current_session_id;
      session.transcriptSessionId = assessment.state.current_session_id;
    }
    if (assessment.state.current_transcript_path) {
      session.transcriptPath = assessment.state.current_transcript_path;
    }
    session.startSource = assessment.state.lineage?.start_source ?? undefined;
    session.previousTranscriptSessionId = assessment.state.lineage?.previous_session_id ?? undefined;
    session.previousTranscriptPath = assessment.state.lineage?.previous_transcript_path ?? undefined;
    if (assessment.state.cwd) {
      session.cwd = assessment.state.cwd;
    }
    if (mapped.state === 'permission' && !session.toolDetail) {
      session.toolDetail = 'Permission request';
    }
    if (mapped.state === 'prompt' && !session.toolDetail) {
      session.toolDetail = assessment.state.notification_type === 'idle_prompt'
        ? 'Claude is waiting for input'
        : 'Needs your input';
    }
    if (mapped.state === 'compact' && !session.toolDetail) {
      session.toolDetail = assessment.state.compact?.summary_excerpt ?? 'Compacting context';
    }
  } else if (assessment.health === 'starting') {
    if (session.state === 'exited') return false;
    session.state = 'starting';
    session.toolName = undefined;
    session.toolDetail = assessment.message;
    session.stateChangedAt = Date.now();
  }

  return previous.state !== session.state
    || previous.toolName !== session.toolName
    || previous.toolDetail !== session.toolDetail
    || previous.activeSubagentCount !== session.activeSubagentCount
    || previous.sidecarHealth !== session.sidecarHealth
    || previous.sidecarMessage !== session.sidecarMessage
    || previous.transcriptSessionId !== session.transcriptSessionId
    || previous.transcriptPath !== session.transcriptPath
    || previous.sessionId !== session.sessionId
    || previous.startSource !== session.startSource
    || previous.previousTranscriptSessionId !== session.previousTranscriptSessionId
    || previous.previousTranscriptPath !== session.previousTranscriptPath
    || previous.cwd !== session.cwd;
}

async function runClaude(args: string[], cwd: string): Promise<CommandResult> {
  const command = formatCommand(args);
  try {
    const { stdout, stderr } = await execFileAsync('claude', args, {
      cwd,
      env: process.env,
      maxBuffer: 1024 * 1024,
    });
    return { step: 'unknown', command, code: 0, stdout, stderr };
  } catch (error) {
    const err = error as { code?: number; stdout?: string; stderr?: string; message?: string };
    return {
      step: 'unknown',
      command,
      code: typeof err.code === 'number' ? err.code : 1,
      stdout: err.stdout ?? '',
      stderr: err.stderr ?? err.message ?? 'claude command failed',
    };
  }
}

function resolveMarketplaceSource(): string {
  return process.env.AEO_SKILL_MARKETPLACE_SOURCE ?? SIDECAR_MARKETPLACE_SOURCE;
}

function withStep(step: string, result: CommandResult): CommandResult {
  return { ...result, step };
}

export async function installOrUpdateRuntime(
  context: vscode.ExtensionContext,
  log: vscode.LogOutputChannel,
): Promise<CommandResult[]> {
  const results: CommandResult[] = [];
  const marketplaceSource = resolveMarketplaceSource();
  invalidateInstalledPluginEntriesCache();

  const marketplaceAdd = normalizeCommandResult(
    withStep(
      'marketplace_add',
      await runClaude(['plugins', 'marketplace', 'add', '--scope', 'user', marketplaceSource], context.extensionPath),
    ),
    [/already on disk/i, /already exists/i, /already configured/i],
  );
  results.push(marketplaceAdd);
  if (marketplaceAdd.code !== 0) {
    for (const result of results) {
      log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
    }
    return results;
  }

  const marketplaceUpdate = withStep(
    'marketplace_update',
    await runClaude(['plugins', 'marketplace', 'update', SIDECAR_MARKETPLACE_NAME], context.extensionPath),
  );
  results.push(marketplaceUpdate);
  if (marketplaceUpdate.code !== 0) {
    for (const result of results) {
      log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
    }
    return results;
  }

  const pluginInstall = normalizeCommandResult(
    withStep(
      'plugin_install',
      await runClaude(['plugins', 'install', '--scope', 'user', `${SIDECAR_PLUGIN_NAME}@${SIDECAR_MARKETPLACE_NAME}`], context.extensionPath),
    ),
    [/already installed/i, /already exists/i, /is already installed/i],
  );
  results.push(pluginInstall);
  if (pluginInstall.code !== 0) {
    for (const result of results) {
      log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
    }
    return results;
  }

  const pluginUpdate = normalizeCommandResult(
    withStep(
      'plugin_update',
      await runClaude(['plugins', 'update', '--scope', 'user', SIDECAR_PLUGIN_NAME], context.extensionPath),
    ),
    [/already up to date/i, /latest version/i],
  );
  results.push(pluginUpdate);
  if (pluginUpdate.code !== 0) {
    for (const result of results) {
      log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
    }
    return results;
  }

  const enable = normalizeCommandResult(
    withStep(
      'plugin_enable',
      await runClaude(['plugins', 'enable', '--scope', 'user', SIDECAR_PLUGIN_NAME], context.extensionPath),
    ),
    [/already enabled/i],
  );
  results.push(enable);
  invalidateInstalledPluginEntriesCache();

  for (const result of results) {
    log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
  }

  return results;
}

export async function removeBundledSidecar(
  log: vscode.LogOutputChannel,
  sessions: Iterable<SessionInfo>,
): Promise<CommandResult[]> {
  const results: CommandResult[] = [];
  invalidateInstalledPluginEntriesCache();
  const uninstall = withStep(
    'plugin_uninstall',
    await runClaude(['plugins', 'uninstall', '--scope', 'user', SIDECAR_PLUGIN_NAME], os.homedir()),
  );
  results.push(uninstall);
  if (uninstall.code !== 0) {
    results.push(withStep(
      'plugin_disable',
      await runClaude(['plugins', 'disable', '--scope', 'user', SIDECAR_PLUGIN_NAME], os.homedir()),
    ));
  }

  const hasLiveSessions = [...sessions].some(session => session.state !== 'exited');
  if (!hasLiveSessions) {
    try {
      await fs.promises.rm(SIDECAR_ROOT, { recursive: true, force: true });
      results.push({ step: 'sidecar_root_cleanup', command: `rm -rf ${SIDECAR_ROOT}`, code: 0, stdout: `Removed ${SIDECAR_ROOT}`, stderr: '' });
    } catch (error) {
      results.push({
        step: 'sidecar_root_cleanup',
        command: `rm -rf ${SIDECAR_ROOT}`,
        code: 1,
        stdout: '',
        stderr: error instanceof Error ? error.message : String(error),
      });
    }
  }

  for (const result of results) {
    log.info(`claude step=${result.step} code=${result.code} stdout=${result.stdout.trim()} stderr=${result.stderr.trim()}`);
  }

  invalidateInstalledPluginEntriesCache();

  return results;
}
