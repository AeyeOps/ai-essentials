import * as assert from 'assert';
import * as vscode from 'vscode';

suite('Extension Test Suite', () => {
  suiteTeardown(() => {
    vscode.window.showInformationMessage('All tests done!');
  });

  test('Extension should be present', () => {
    const ext = vscode.extensions.getExtension('my-publisher-id.my-sample-extension');
    assert.ok(ext, 'Extension should be installed');
  });

  test('Command should be registered', async () => {
    const commands = await vscode.commands.getCommands(true);
    assert.ok(
      commands.includes('mySampleExtension.helloWorld'),
      'helloWorld command should be registered'
    );
  });

  test('Command should execute without error', async () => {
    await assert.doesNotReject(
      async () => vscode.commands.executeCommand('mySampleExtension.helloWorld')
    );
  });

  test('Extension should activate', async () => {
    const ext = vscode.extensions.getExtension('my-publisher-id.my-sample-extension');
    if (ext && !ext.isActive) {
      await ext.activate();
    }
    assert.ok(ext?.isActive, 'Extension should be active after activation');
  });
});
