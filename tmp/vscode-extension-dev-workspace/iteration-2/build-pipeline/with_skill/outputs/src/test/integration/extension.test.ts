import * as assert from 'assert';
import * as vscode from 'vscode';

suite('Extension Integration Tests', () => {
  suiteTeardown(() => {
    vscode.window.showInformationMessage('All tests done!');
  });

  test('Extension should be present', () => {
    const ext = vscode.extensions.getExtension('my-publisher-id.my-extension');
    assert.ok(ext, 'Extension not found');
  });

  test('Extension should activate', async () => {
    const ext = vscode.extensions.getExtension('my-publisher-id.my-extension');
    assert.ok(ext, 'Extension not found');
    await ext.activate();
    assert.strictEqual(ext.isActive, true);
  });

  test('helloWorld command should be registered', async () => {
    const commands = await vscode.commands.getCommands(true);
    assert.ok(
      commands.includes('myExtension.helloWorld'),
      'Command myExtension.helloWorld not registered'
    );
  });

  test('helloWorld command should execute without error', async () => {
    await assert.doesNotReject(
      vscode.commands.executeCommand('myExtension.helloWorld')
    );
  });
});
