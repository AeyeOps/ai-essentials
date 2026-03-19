import * as vscode from "vscode";
import { ContainerInfo } from "./dockerClient";

export class ContainerItem extends vscode.TreeItem {
  public readonly containerId: string;
  public readonly containerName: string;

  constructor(public readonly container: ContainerInfo) {
    const statusDot = ContainerItem.getStatusDot(container.state);
    const label = `${statusDot} ${container.name}`;

    super(label, vscode.TreeItemCollapsibleState.None);

    this.containerId = container.id;
    this.containerName = container.name;
    this.tooltip = this.buildTooltip(container);
    this.description = container.image;
    this.contextValue = `container-${container.state}`;

    if (container.id) {
      this.command = {
        command: "dockerTreeView.openLogs",
        title: "Open Container Logs",
        arguments: [this],
      };
    }
  }

  private static getStatusDot(
    state: string
  ): string {
    switch (state) {
      case "running":
        return "\u{1F7E2}";
      case "paused":
        return "\u{1F7E1}";
      case "restarting":
        return "\u{1F7E1}";
      case "exited":
        return "\u{1F534}";
      case "dead":
        return "\u{1F534}";
      case "created":
        return "\u{26AA}";
      default:
        return "\u{26AA}";
    }
  }

  private buildTooltip(container: ContainerInfo): vscode.MarkdownString {
    const md = new vscode.MarkdownString();
    md.appendMarkdown(`**${container.name}**\n\n`);
    md.appendMarkdown(`- **Image:** ${container.image}\n`);
    md.appendMarkdown(`- **State:** ${container.state}\n`);
    md.appendMarkdown(`- **Status:** ${container.status}\n`);
    md.appendMarkdown(`- **ID:** \`${container.id.substring(0, 12)}\`\n`);
    return md;
  }
}
