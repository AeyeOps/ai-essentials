import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

export type ContainerState = 'running' | 'paused' | 'exited' | 'created' | 'restarting' | 'removing' | 'dead';

export interface ContainerInfo {
  id: string;
  name: string;
  image: string;
  state: ContainerState;
  status: string;
  ports: string;
  createdAt: string;
}

interface DockerPsEntry {
  ID: string;
  Names: string;
  Image: string;
  State: string;
  Status: string;
  Ports: string;
  CreatedAt: string;
}

function parseState(raw: string): ContainerState {
  const normalized = raw.toLowerCase().trim();
  const valid: ContainerState[] = ['running', 'paused', 'exited', 'created', 'restarting', 'removing', 'dead'];
  if (valid.includes(normalized as ContainerState)) {
    return normalized as ContainerState;
  }
  return 'exited';
}

export async function listContainers(showAll: boolean): Promise<ContainerInfo[]> {
  const args = ['ps', '--format', '{{json .}}', '--no-trunc'];
  if (showAll) {
    args.push('-a');
  }

  const { stdout } = await execFileAsync('docker', args, { timeout: 10000 });

  if (!stdout.trim()) {
    return [];
  }

  const lines = stdout.trim().split('\n');
  const containers: ContainerInfo[] = [];

  for (const line of lines) {
    if (!line.trim()) {
      continue;
    }
    const entry: DockerPsEntry = JSON.parse(line);
    containers.push({
      id: entry.ID,
      name: entry.Names,
      image: entry.Image,
      state: parseState(entry.State),
      status: entry.Status,
      ports: entry.Ports,
      createdAt: entry.CreatedAt,
    });
  }

  return containers;
}

export async function startContainer(id: string): Promise<void> {
  await execFileAsync('docker', ['start', id], { timeout: 30000 });
}

export async function stopContainer(id: string): Promise<void> {
  await execFileAsync('docker', ['stop', id], { timeout: 30000 });
}

export async function restartContainer(id: string): Promise<void> {
  await execFileAsync('docker', ['restart', id], { timeout: 30000 });
}
