import * as vscode from 'vscode';
import { ContainerTreeProvider, ContainerTreeItem } from './containerTreeProvider';
import { startContainer, stopContainer, restartContainer } from './docker';

export function activate(context: vscode.ExtensionContext): void {
  const provider = new ContainerTreeProvider();

  const treeView = vscode.window.createTreeView('dockerContainers', {
    treeDataProvider: provider,
    showCollapseAll: false,
  });

  const logTerminals = new Map<string, vscode.Terminal>();

  function cleanupTerminal(name: string): void {
    logTerminals.delete(name);
  }

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal(terminal => {
      for (const [key, t] of logTerminals.entries()) {
        if (t === terminal) {
          cleanupTerminal(key);
          break;
        }
      }
    })
  );

  context.subscriptions.push(
    treeView,

    vscode.commands.registerCommand('dockerContainers.refresh', () => {
      provider.refresh();
    }),

    vscode.commands.registerCommand('dockerContainers.openLogs', (item: ContainerTreeItem) => {
      const container = item.container;
      const terminalName = `Docker: ${container.name}`;

      const existing = logTerminals.get(terminalName);
      if (existing) {
        existing.show();
        return;
      }

      const terminal = vscode.window.createTerminal({
        name: terminalName,
        isTransient: true,
      });
      terminal.sendText(`docker logs -f --tail 200 ${container.id}`);
      terminal.show();
      logTerminals.set(terminalName, terminal);
    }),

    vscode.commands.registerCommand('dockerContainers.start', async (item: ContainerTreeItem) => {
      try {
        await startContainer(item.container.id);
        provider.refresh();
      } catch (err) {
        vscode.window.showErrorMessage(`Failed to start ${item.container.name}: ${err}`);
      }
    }),

    vscode.commands.registerCommand('dockerContainers.stop', async (item: ContainerTreeItem) => {
      try {
        await stopContainer(item.container.id);
        provider.refresh();
      } catch (err) {
        vscode.window.showErrorMessage(`Failed to stop ${item.container.name}: ${err}`);
      }
    }),

    vscode.commands.registerCommand('dockerContainers.restart', async (item: ContainerTreeItem) => {
      try {
        await restartContainer(item.container.id);
        provider.refresh();
      } catch (err) {
        vscode.window.showErrorMessage(`Failed to restart ${item.container.name}: ${err}`);
      }
    })
  );

  const config = vscode.workspace.getConfiguration('dockerContainers');
  let refreshInterval = config.get<number>('refreshInterval', 5000);

  let autoRefreshTimer: ReturnType<typeof setInterval> | undefined;

  function startAutoRefresh(): void {
    stopAutoRefresh();
    if (refreshInterval > 0) {
      autoRefreshTimer = setInterval(() => {
        provider.refresh();
      }, refreshInterval);
    }
  }

  function stopAutoRefresh(): void {
    if (autoRefreshTimer !== undefined) {
      clearInterval(autoRefreshTimer);
      autoRefreshTimer = undefined;
    }
  }

  startAutoRefresh();

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('dockerContainers.refreshInterval')) {
        refreshInterval = vscode.workspace
          .getConfiguration('dockerContainers')
          .get<number>('refreshInterval', 5000);
        startAutoRefresh();
      }
      if (e.affectsConfiguration('dockerContainers.showAllContainers')) {
        provider.refresh();
      }
    }),
    { dispose: () => stopAutoRefresh() }
  );
}

export function deactivate(): void {
  // Cleanup handled by subscriptions
}
