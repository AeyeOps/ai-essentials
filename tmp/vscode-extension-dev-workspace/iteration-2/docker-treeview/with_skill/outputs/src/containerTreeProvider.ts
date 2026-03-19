import * as vscode from 'vscode';
import { ContainerInfo, ContainerState } from './docker.js';

export class ContainerTreeItem extends vscode.TreeItem {
  constructor(public readonly container: ContainerInfo) {
    super(container.name, vscode.TreeItemCollapsibleState.None);

    this.description = `${container.image} - ${container.status}`;
    this.tooltip = this.buildTooltip();
    this.iconPath = this.getStatusIcon();
    this.contextValue = this.getContextValue();
    this.command = {
      command: 'dockerTreeView.openLogs',
      title: 'Open Container Logs',
      arguments: [this],
    };
  }

  private buildTooltip(): vscode.MarkdownString {
    const md = new vscode.MarkdownString();
    md.appendMarkdown(`**${this.container.name}**\n\n`);
    md.appendMarkdown(`- **Image:** ${this.container.image}\n`);
    md.appendMarkdown(`- **State:** ${this.container.state}\n`);
    md.appendMarkdown(`- **Status:** ${this.container.status}\n`);
    if (this.container.ports) {
      md.appendMarkdown(`- **Ports:** ${this.container.ports}\n`);
    }
    md.appendMarkdown(`- **ID:** \`${this.container.id.substring(0, 12)}\`\n`);
    return md;
  }

  private getStatusIcon(): vscode.ThemeIcon {
    const colorMap: Record<ContainerState, string> = {
      running: 'charts.green',
      paused: 'charts.yellow',
      exited: 'charts.red',
      created: 'charts.blue',
      restarting: 'charts.orange',
      removing: 'charts.orange',
      dead: 'charts.red',
    };

    const color = colorMap[this.container.state] ?? 'charts.red';
    return new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor(color));
  }

  private getContextValue(): string {
    switch (this.container.state) {
      case 'running':
      case 'restarting':
        return 'running';
      case 'paused':
        return 'running';
      default:
        return 'stopped';
    }
  }
}

export class ContainerTreeProvider implements vscode.TreeDataProvider<ContainerTreeItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<ContainerTreeItem | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private items: ContainerTreeItem[] = [];

  setContainers(containers: ContainerInfo[]): void {
    this.items = containers.map(c => new ContainerTreeItem(c));
    this._onDidChangeTreeData.fire();
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: ContainerTreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(element?: ContainerTreeItem): ContainerTreeItem[] {
    if (element) {
      return [];
    }
    return this.items;
  }
}
