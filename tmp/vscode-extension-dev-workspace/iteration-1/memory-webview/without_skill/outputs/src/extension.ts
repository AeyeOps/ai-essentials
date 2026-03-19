import * as vscode from 'vscode';
import { MemoryMonitorPanel } from './memoryMonitorPanel';

export function activate(context: vscode.ExtensionContext): void {
  const showCommand = vscode.commands.registerCommand(
    'memoryMonitor.show',
    () => {
      MemoryMonitorPanel.createOrShow(context.extensionUri);
    }
  );

  context.subscriptions.push(showCommand);

  if (MemoryMonitorPanel.currentPanel) {
    MemoryMonitorPanel.currentPanel.dispose();
  }
}

export function deactivate(): void {
  MemoryMonitorPanel.currentPanel?.dispose();
}
