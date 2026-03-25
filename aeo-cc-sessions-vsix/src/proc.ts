import * as fs from 'node:fs';

export interface ProcStat {
  ppid: number;
  startTicks: number;
}

export interface ProcInfo extends ProcStat {
  pid: number;
  cmdlineArgs?: string[];
  cwd?: string;
  exe?: string;
  tty?: string;
}

export function readProcStat(pid: number): ProcStat | undefined {
  try {
    const raw = fs.readFileSync(`/proc/${pid}/stat`, 'utf-8');
    const closeParen = raw.lastIndexOf(')');
    if (closeParen === -1) return undefined;
    const fields = raw.slice(closeParen + 2).split(' ');
    if (fields.length < 20) return undefined;
    const ppid = parseInt(fields[1], 10);
    const startTicks = parseInt(fields[19], 10);
    if (Number.isNaN(ppid) || Number.isNaN(startTicks)) return undefined;
    return { ppid, startTicks };
  } catch {
    return undefined;
  }
}

export function readCmdlineArgs(pid: number): string[] | undefined {
  try {
    const raw = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf-8');
    return raw.split('\0').filter(Boolean);
  } catch {
    return undefined;
  }
}

function readProcLink(linkPath: string): string | undefined {
  try {
    return fs.readlinkSync(linkPath);
  } catch {
    return undefined;
  }
}

export function readProcInfo(pid: number): ProcInfo | undefined {
  const stat = readProcStat(pid);
  if (!stat) return undefined;
  return {
    pid,
    ppid: stat.ppid,
    startTicks: stat.startTicks,
    cmdlineArgs: readCmdlineArgs(pid),
    cwd: readProcLink(`/proc/${pid}/cwd`),
    exe: readProcLink(`/proc/${pid}/exe`),
    tty: readProcLink(`/proc/${pid}/fd/0`),
  };
}

export function readProcChain(pid: number, stopPid?: number, maxDepth = 16): ProcInfo[] {
  const chain: ProcInfo[] = [];
  const seen = new Set<number>();
  let currentPid: number | undefined = pid;

  while (currentPid && currentPid > 0 && !seen.has(currentPid) && chain.length < maxDepth) {
    seen.add(currentPid);
    const info = readProcInfo(currentPid);
    if (!info) break;
    chain.push(info);
    if (stopPid && currentPid === stopPid) break;
    if (!info.ppid || info.ppid <= 1) break;
    currentPid = info.ppid;
  }

  return chain;
}
