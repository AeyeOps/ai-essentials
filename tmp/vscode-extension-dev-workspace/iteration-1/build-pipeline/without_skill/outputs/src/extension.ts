import * as vscode from "vscode";

export function activate(context: vscode.ExtensionContext): void {
  const disposable = vscode.commands.registerCommand(
    "my-extension.helloWorld",
    () => {
      vscode.window.showInformationMessage("Hello World from My Extension!");
    }
  );

  context.subscriptions.push(disposable);
}

export function deactivate(): void {}
