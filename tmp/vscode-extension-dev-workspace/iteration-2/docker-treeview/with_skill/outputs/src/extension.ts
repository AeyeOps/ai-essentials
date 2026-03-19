import * as vscode from 'vscode';
import { ContainerTreeProvider, ContainerTreeItem } from './containerTreeProvider.js';
import { listContainers, startContainer, stopContainer, restartContainer } from './docker.js';

let autoRefreshTimer: ReturnType<typeof setInterval> | undefined;

async function refreshContainers(provider: ContainerTreeProvider): Promise<void> {
  try {
    const config = vscode.workspace.getConfiguration('dockerTreeView');
    const showAll = config.get<boolean>('showAllContainers', true);
    const containers = await listContainers(showAll);
    provider.setContainers(containers);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('ENOENT') || message.includes('not found')) {
      vscode.window.showErrorMessage('Docker CLI not found. Make sure Docker is installed and in PATH.');
    } else if (message.includes('permission denied')) {
      vscode.window.showErrorMessage('Permission denied accessing Docker. Check your user is in the docker group.');
    } else {
      vscode.window.showErrorMessage(`Docker error: ${message}`);
    }
    provider.setContainers([]);
  }
}

function setupAutoRefresh(provider: ContainerTreeProvider): void {
  if (autoRefreshTimer) {
    clearInterval(autoRefreshTimer);
    autoRefreshTimer = undefined;
  }

  const config = vscode.workspace.getConfiguration('dockerTreeView');
  const interval = config.get<number>('refreshInterval', 5000);

  if (interval > 0) {
    autoRefreshTimer = setInterval(() => {
      refreshContainers(provider);
    }, interval);
  }
}

const terminalMap = new Map<string, vscode.Terminal>();

function openContainerLogs(item: ContainerTreeItem): void {
  const containerId = item.container.id;
  const containerName = item.container.name;

  const existing = terminalMap.get(containerId);
  if (existing) {
    const stillOpen = vscode.window.terminals.find(t => t === existing);
    if (stillOpen) {
      existing.show();
      return;
    }
    terminalMap.delete(containerId);
  }

  const terminal = vscode.window.createTerminal({
    name: `Logs: ${containerName}`,
  });
  terminal.show();
  terminal.sendText(`docker logs -f ${containerId}`);
  terminalMap.set(containerId, terminal);
}

export function activate(context: vscode.ExtensionContext): void {
  const provider = new ContainerTreeProvider();

  const treeView = vscode.window.createTreeView('dockerContainers', {
    treeDataProvider: provider,
    showCollapseAll: false,
  });

  context.subscriptions.push(treeView);

  context.subscriptions.push(
    vscode.commands.registerCommand('dockerTreeView.refresh', () => {
      refreshContainers(provider);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dockerTreeView.openLogs', (item: ContainerTreeItem) => {
      if (item) {
        openContainerLogs(item);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dockerTreeView.startContainer', async (item: ContainerTreeItem) => {
      if (!item) {
        return;
      }
      try {
        await startContainer(item.container.id);
        vscode.window.showInformationMessage(`Started container: ${item.container.name}`);
        refreshContainers(provider);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        vscode.window.showErrorMessage(`Failed to start container: ${message}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dockerTreeView.stopContainer', async (item: ContainerTreeItem) => {
      if (!item) {
        return;
      }
      try {
        await stopContainer(item.container.id);
        vscode.window.showInformationMessage(`Stopped container: ${item.container.name}`);
        refreshContainers(provider);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        vscode.window.showErrorMessage(`Failed to stop container: ${message}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dockerTreeView.restartContainer', async (item: ContainerTreeItem) => {
      if (!item) {
        return;
      }
      try {
        await restartContainer(item.container.id);
        vscode.window.showInformationMessage(`Restarted container: ${item.container.name}`);
        refreshContainers(provider);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        vscode.window.showErrorMessage(`Failed to restart container: ${message}`);
      }
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('dockerTreeView.refreshInterval')) {
        setupAutoRefresh(provider);
      }
      if (e.affectsConfiguration('dockerTreeView.showAllContainers')) {
        refreshContainers(provider);
      }
    })
  );

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal(terminal => {
      for (const [id, term] of terminalMap.entries()) {
        if (term === terminal) {
          terminalMap.delete(id);
          break;
        }
      }
    })
  );

  context.subscriptions.push({ dispose: () => {
    if (autoRefreshTimer) {
      clearInterval(autoRefreshTimer);
      autoRefreshTimer = undefined;
    }
    terminalMap.clear();
  }});

  refreshContainers(provider);
  setupAutoRefresh(provider);
}

export function deactivate(): void {
  if (autoRefreshTimer) {
    clearInterval(autoRefreshTimer);
    autoRefreshTimer = undefined;
  }
  terminalMap.clear();
}
