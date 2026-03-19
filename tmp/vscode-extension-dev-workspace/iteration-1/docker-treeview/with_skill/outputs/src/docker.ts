import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export type ContainerState = 'running' | 'exited' | 'paused' | 'restarting' | 'created' | 'removing' | 'dead';

export interface DockerContainer {
  id: string;
  name: string;
  image: string;
  state: ContainerState;
  status: string;
  ports: string;
}

export async function listContainers(showAll: boolean): Promise<DockerContainer[]> {
  const format = '{{.ID}}\\t{{.Names}}\\t{{.Image}}\\t{{.State}}\\t{{.Status}}\\t{{.Ports}}';
  const allFlag = showAll ? '-a' : '';
  const cmd = `docker ps ${allFlag} --format "${format}" --no-trunc`;

  try {
    const { stdout } = await execAsync(cmd, { timeout: 10000 });
    if (!stdout.trim()) {
      return [];
    }

    return stdout
      .trim()
      .split('\n')
      .map(line => {
        const [id, name, image, state, status, ports] = line.split('\t');
        return {
          id: id.substring(0, 12),
          name,
          image,
          state: normalizeState(state),
          status,
          ports: ports || '',
        };
      });
  } catch {
    return [];
  }
}

function normalizeState(raw: string): ContainerState {
  const lower = raw.toLowerCase().trim();
  if (lower === 'running') { return 'running'; }
  if (lower === 'paused') { return 'paused'; }
  if (lower === 'restarting') { return 'restarting'; }
  if (lower === 'created') { return 'created'; }
  if (lower === 'removing') { return 'removing'; }
  if (lower === 'dead') { return 'dead'; }
  return 'exited';
}

export async function startContainer(id: string): Promise<void> {
  await execAsync(`docker start ${id}`, { timeout: 30000 });
}

export async function stopContainer(id: string): Promise<void> {
  await execAsync(`docker stop ${id}`, { timeout: 30000 });
}

export async function restartContainer(id: string): Promise<void> {
  await execAsync(`docker restart ${id}`, { timeout: 30000 });
}
