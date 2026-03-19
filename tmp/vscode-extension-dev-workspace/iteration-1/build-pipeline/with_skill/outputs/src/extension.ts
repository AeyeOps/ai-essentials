import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
  const disposable = vscode.commands.registerCommand('mySampleExtension.helloWorld', () => {
    vscode.window.showInformationMessage('Hello from My Sample Extension!');
  });

  context.subscriptions.push(disposable);
}

export function deactivate() {}
