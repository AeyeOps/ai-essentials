import * as vscode from 'vscode';
import { DockerContainer, ContainerState, listContainers } from './docker';

export class ContainerTreeItem extends vscode.TreeItem {
  constructor(public readonly container: DockerContainer) {
    super(container.name, vscode.TreeItemCollapsibleState.None);

    this.description = `${container.image} - ${container.status}`;
    this.tooltip = new vscode.MarkdownString(
      [
        `**${container.name}**`,
        `- **Image:** ${container.image}`,
        `- **ID:** ${container.id}`,
        `- **State:** ${container.state}`,
        `- **Status:** ${container.status}`,
        container.ports ? `- **Ports:** ${container.ports}` : '',
      ]
        .filter(Boolean)
        .join('\n')
    );

    this.iconPath = ContainerTreeItem.iconForState(container.state);
    this.contextValue = ContainerTreeItem.contextForState(container.state);

    this.command = {
      command: 'dockerContainers.openLogs',
      title: 'Open Logs',
      arguments: [this],
    };
  }

  private static iconForState(state: ContainerState): vscode.ThemeIcon {
    switch (state) {
      case 'running':
        return new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor('charts.green'));
      case 'paused':
        return new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor('charts.yellow'));
      case 'restarting':
        return new vscode.ThemeIcon('sync~spin', new vscode.ThemeColor('charts.blue'));
      default:
        return new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor('charts.red'));
    }
  }

  private static contextForState(state: ContainerState): string {
    switch (state) {
      case 'running':
        return 'running';
      case 'paused':
        return 'paused';
      case 'restarting':
        return 'restarting';
      default:
        return 'stopped';
    }
  }
}

export class ContainerTreeProvider implements vscode.TreeDataProvider<ContainerTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<ContainerTreeItem | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private containers: ContainerTreeItem[] = [];

  async getChildren(_element?: ContainerTreeItem): Promise<ContainerTreeItem[]> {
    if (_element) {
      return [];
    }

    const showAll = vscode.workspace
      .getConfiguration('dockerContainers')
      .get<boolean>('showAllContainers', true);

    const containers = await listContainers(showAll);

    containers.sort((a, b) => {
      const order: Record<ContainerState, number> = {
        running: 0,
        restarting: 1,
        paused: 2,
        created: 3,
        exited: 4,
        removing: 5,
        dead: 6,
      };
      return (order[a.state] ?? 99) - (order[b.state] ?? 99);
    });

    this.containers = containers.map(c => new ContainerTreeItem(c));
    return this.containers;
  }

  getTreeItem(element: ContainerTreeItem): vscode.TreeItem {
    return element;
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }
}
