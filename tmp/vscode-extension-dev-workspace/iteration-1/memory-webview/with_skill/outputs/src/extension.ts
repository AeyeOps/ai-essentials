import * as vscode from 'vscode';
import { MemoryMonitorPanel } from './memoryMonitorPanel';

export function activate(context: vscode.ExtensionContext) {
  const showCommand = vscode.commands.registerCommand('memoryMonitor.show', () => {
    MemoryMonitorPanel.createOrShow(context);
  });

  vscode.window.registerWebviewPanelSerializer(MemoryMonitorPanel.viewType, {
    async deserializeWebviewPanel(panel: vscode.WebviewPanel, state: unknown) {
      MemoryMonitorPanel.revive(panel, context, state);
    }
  });

  context.subscriptions.push(showCommand);
}

export function deactivate() {}
