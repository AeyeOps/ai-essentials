import * as assert from "assert";
import * as vscode from "vscode";

suite("Extension Test Suite", () => {
  vscode.window.showInformationMessage("Start all tests.");

  test("Extension should be present", () => {
    assert.ok(
      vscode.extensions.getExtension("your-publisher-id.my-extension")
    );
  });

  test("Extension should activate", async () => {
    const ext = vscode.extensions.getExtension(
      "your-publisher-id.my-extension"
    );
    assert.ok(ext);
    await ext.activate();
    assert.strictEqual(ext.isActive, true);
  });

  test("Should register helloWorld command", async () => {
    const commands = await vscode.commands.getCommands(true);
    assert.ok(commands.includes("my-extension.helloWorld"));
  });
});
