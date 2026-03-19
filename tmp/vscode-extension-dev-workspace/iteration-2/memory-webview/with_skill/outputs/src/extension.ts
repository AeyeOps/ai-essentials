import * as vscode from 'vscode';
import { MemoryChartPanel } from './memoryChartPanel';

export function activate(context: vscode.ExtensionContext) {
  const showCommand = vscode.commands.registerCommand('memoryChart.show', () => {
    MemoryChartPanel.createOrShow(context);
  });

  context.subscriptions.push(showCommand);

  vscode.window.registerWebviewPanelSerializer('memoryChart', {
    async deserializeWebviewPanel(panel: vscode.WebviewPanel, state: unknown) {
      MemoryChartPanel.restore(panel, context, state);
    }
  });
}

export function deactivate() {}
