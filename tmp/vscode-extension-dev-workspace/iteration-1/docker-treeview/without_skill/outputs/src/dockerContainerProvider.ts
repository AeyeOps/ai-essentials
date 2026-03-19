import * as vscode from "vscode";
import { ContainerItem } from "./containerItem";
import { DockerClient, ContainerInfo } from "./dockerClient";

export class DockerContainerProvider
  implements vscode.TreeDataProvider<ContainerItem>
{
  private _onDidChangeTreeData = new vscode.EventEmitter<
    ContainerItem | undefined | null | void
  >();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private dockerClient: DockerClient;

  constructor() {
    this.dockerClient = new DockerClient();
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: ContainerItem): vscode.TreeItem {
    return element;
  }

  async getChildren(element?: ContainerItem): Promise<ContainerItem[]> {
    if (element) {
      return [];
    }

    try {
      const containers = await this.dockerClient.listContainers();

      if (containers.length === 0) {
        return [this.createMessageItem("No containers found")];
      }

      return containers.map(
        (container) => new ContainerItem(container)
      );
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Unknown error";
      return [this.createMessageItem(`Docker error: ${message}`)];
    }
  }

  private createMessageItem(message: string): ContainerItem {
    const info: ContainerInfo = {
      id: "",
      name: message,
      image: "",
      state: "exited",
      status: "",
    };
    const item = new ContainerItem(info);
    item.command = undefined;
    return item;
  }
}
