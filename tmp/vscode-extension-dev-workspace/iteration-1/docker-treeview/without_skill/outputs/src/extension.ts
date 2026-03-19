import * as vscode from "vscode";
import { DockerContainerProvider } from "./dockerContainerProvider";
import { ContainerItem } from "./containerItem";

export function activate(context: vscode.ExtensionContext): void {
  const provider = new DockerContainerProvider();

  const treeView = vscode.window.createTreeView("dockerContainers", {
    treeDataProvider: provider,
    showCollapseAll: false,
  });

  const refreshCmd = vscode.commands.registerCommand(
    "dockerTreeView.refresh",
    () => {
      provider.refresh();
    }
  );

  const openLogsCmd = vscode.commands.registerCommand(
    "dockerTreeView.openLogs",
    (item: ContainerItem) => {
      const terminal = vscode.window.createTerminal({
        name: `Logs: ${item.containerName}`,
        shellPath: "/usr/bin/env",
        shellArgs: ["docker", "logs", "-f", item.containerId],
      });
      terminal.show();
    }
  );

  const autoRefresh = setInterval(() => {
    provider.refresh();
  }, 5000);

  context.subscriptions.push(
    treeView,
    refreshCmd,
    openLogsCmd,
    { dispose: () => clearInterval(autoRefresh) }
  );
}

export function deactivate(): void {}
