import { execFile } from "child_process";

export interface ContainerInfo {
  id: string;
  name: string;
  image: string;
  state: string;
  status: string;
}

export class DockerClient {
  async listContainers(): Promise<ContainerInfo[]> {
    const format =
      '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}","state":"{{.State}}","status":"{{.Status}}"}';

    const stdout = await this.exec("docker", [
      "ps",
      "-a",
      "--no-trunc",
      "--format",
      format,
    ]);

    if (!stdout.trim()) {
      return [];
    }

    const lines = stdout.trim().split("\n");
    const containers: ContainerInfo[] = [];

    for (const line of lines) {
      try {
        const parsed = JSON.parse(line) as ContainerInfo;
        containers.push(parsed);
      } catch {
        continue;
      }
    }

    containers.sort((a, b) => {
      const stateOrder: Record<string, number> = {
        running: 0,
        paused: 1,
        restarting: 2,
        created: 3,
        exited: 4,
        dead: 5,
      };
      const orderA = stateOrder[a.state] ?? 99;
      const orderB = stateOrder[b.state] ?? 99;
      if (orderA !== orderB) {
        return orderA - orderB;
      }
      return a.name.localeCompare(b.name);
    });

    return containers;
  }

  private exec(command: string, args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      execFile(
        command,
        args,
        { timeout: 10000, maxBuffer: 1024 * 1024 },
        (error, stdout, stderr) => {
          if (error) {
            const msg = stderr?.trim() || error.message;
            reject(new Error(msg));
            return;
          }
          resolve(stdout);
        }
      );
    });
  }
}
