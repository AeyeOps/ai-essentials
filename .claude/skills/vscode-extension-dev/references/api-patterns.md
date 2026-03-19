# VS Code Extension API Patterns

Detailed code examples for the most commonly used VS Code extension APIs. This file supplements
the main SKILL.md — read when implementing any of these patterns.

## Table of Contents

- [TreeView](#treeview)
- [Webview Panel](#webview-panel)
- [WebviewView Provider](#webviewview-provider)
- [Terminal API](#terminal-api)
- [FileSystemWatcher](#filesystemwatcher)
- [Status Bar](#status-bar)
- [Commands](#commands)
- [Configuration](#configuration)
- [Disposable Pattern](#disposable-pattern)

---

## TreeView

### TreeDataProvider Implementation

```typescript
import * as vscode from 'vscode';

interface MyItem {
  name: string;
  children?: MyItem[];
}

class MyTreeProvider implements vscode.TreeDataProvider<MyItem> {
  private _onDidChangeTreeData = new vscode.EventEmitter<MyItem | undefined | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  private items: MyItem[] = [];

  getTreeItem(element: MyItem): vscode.TreeItem {
    const item = new vscode.TreeItem(
      element.name,
      element.children?.length
        ? vscode.TreeItemCollapsibleState.Collapsed
        : vscode.TreeItemCollapsibleState.None
    );

    // Secondary text shown after the label
    item.description = 'some detail';

    // Hover text (string or MarkdownString)
    item.tooltip = new vscode.MarkdownString(`**${element.name}**\nMore info here`);

    // Icon — use ThemeIcon for built-in codicons, or custom SVG
    item.iconPath = new vscode.ThemeIcon('circle-filled', new vscode.ThemeColor('charts.green'));

    // Enables filtering in view/item/context menus via "viewItem == myContext"
    item.contextValue = 'myContext';

    // Command executed when user clicks this item
    item.command = {
      command: 'myExt.selectItem',
      title: 'Select',
      arguments: [element]
    };

    return item;
  }

  getChildren(element?: MyItem): MyItem[] {
    if (!element) {
      return this.items;  // root level
    }
    return element.children ?? [];
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();  // undefined = refresh entire tree
  }

  refreshItem(item: MyItem): void {
    this._onDidChangeTreeData.fire(item);  // refresh specific subtree
  }
}
```

### Registration

```typescript
// Option 1: Basic — no programmatic access to the view
vscode.window.registerTreeDataProvider('myView', provider);

// Option 2: Full — returns TreeView object for programmatic operations
const treeView = vscode.window.createTreeView('myView', {
  treeDataProvider: provider,
  showCollapseAll: true,   // adds collapse-all button to toolbar
  canSelectMany: false,    // multi-select support
});

// Programmatic operations
treeView.reveal(item, { select: true, focus: true, expand: true });
treeView.title = 'Updated Title';
treeView.badge = { value: 5, tooltip: '5 items' };
treeView.message = 'Loading...';  // shown at top of view

context.subscriptions.push(treeView);
```

### ThemeIcon Reference

Common codicons for tree items: `circle-filled`, `circle-outline`, `check`, `error`, `warning`,
`info`, `file`, `folder`, `symbol-method`, `symbol-property`, `gear`, `refresh`, `play`, `debug`,
`terminal`, `eye`, `edit`, `trash`, `add`, `remove`.

ThemeColors for icons: `charts.green`, `charts.yellow`, `charts.blue`, `charts.red`,
`charts.orange`, `charts.purple`, `errorForeground`, `warningForeground`.

Full codicon list: https://microsoft.github.io/vscode-codicons/dist/codicon.html

---

## Webview Panel

### Creating a Webview Panel

```typescript
const panel = vscode.window.createWebviewPanel(
  'myPanel',                       // internal identifier
  'My Panel Title',                // displayed in tab
  vscode.ViewColumn.One,           // editor column
  {
    enableScripts: true,
    localResourceRoots: [
      vscode.Uri.joinPath(context.extensionUri, 'media')
    ],
    retainContextWhenHidden: false  // true = keep JS running when tab hidden
  }
);

// Tab icon (can use ThemeIcon as of v1.110)
panel.iconPath = new vscode.ThemeIcon('dashboard');
```

### Setting HTML Content

```typescript
function getWebviewContent(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  // Convert local file paths to webview-safe URIs
  const scriptUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'main.js')
  );
  const styleUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'style.css')
  );
  const nonce = getNonce();

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy"
    content="default-src 'none';
      style-src ${webview.cspSource};
      script-src 'nonce-${nonce}';
      img-src ${webview.cspSource} https:;
      font-src ${webview.cspSource};">
  <link href="${styleUri}" rel="stylesheet">
</head>
<body>
  <div id="app"></div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

function getNonce(): string {
  let text = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return text;
}
```

### Message Passing

```typescript
// Extension → Webview
panel.webview.postMessage({ type: 'update', data: myData });

// Webview → Extension
panel.webview.onDidReceiveMessage(
  message => {
    switch (message.type) {
      case 'ready':
        // Webview loaded, send initial data
        break;
      case 'action':
        vscode.commands.executeCommand(message.command);
        break;
    }
  },
  undefined,
  context.subscriptions
);
```

In the webview's JavaScript:

```javascript
const vscode = acquireVsCodeApi();  // call once, reuse

// Receive from extension
window.addEventListener('message', event => {
  const message = event.data;
  if (message.type === 'update') {
    renderData(message.data);
  }
});

// Send to extension
vscode.postMessage({ type: 'action', command: 'myExt.doThing' });

// Persist lightweight state across visibility changes
vscode.setState({ scrollPosition: 42 });
const state = vscode.getState();  // { scrollPosition: 42 }
```

### Lifecycle

```typescript
// Detect visibility changes
panel.onDidChangeViewState(e => {
  if (e.webviewPanel.visible) {
    // Panel became visible — update content
  }
});

// Cleanup when panel is closed
panel.onDidDispose(() => {
  // Release resources
}, null, context.subscriptions);
```

### Serialization (restore on restart)

```typescript
// In activate():
vscode.window.registerWebviewPanelSerializer('myPanel', {
  async deserializeWebviewPanel(panel: vscode.WebviewPanel, state: any) {
    panel.webview.html = getWebviewContent(panel.webview, context.extensionUri);
    if (state) {
      panel.webview.postMessage({ type: 'restore', data: state });
    }
  }
});

// In package.json:
"activationEvents": ["onWebviewPanel:myPanel"]
```

### Theming CSS

Webviews automatically get VS Code theme CSS variables:

```css
body {
  color: var(--vscode-editor-foreground);
  background-color: var(--vscode-editor-background);
  font-family: var(--vscode-editor-font-family);
  font-size: var(--vscode-editor-font-size);
}

/* Theme-specific styles */
body.vscode-light { /* light theme overrides */ }
body.vscode-dark { /* dark theme overrides */ }
body.vscode-high-contrast { /* high contrast overrides */ }

/* Accessibility */
body.vscode-reduce-motion * { transition: none !important; }
```

---

## WebviewView Provider

For webviews embedded in the sidebar or panel (not standalone editor tabs):

```typescript
class MyWebviewViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = 'myExt.sidebarView';

  constructor(private readonly extensionUri: vscode.Uri) {}

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ) {
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };

    webviewView.webview.html = this.getHtml(webviewView.webview);

    webviewView.webview.onDidReceiveMessage(message => {
      // Handle messages
    });
  }

  private getHtml(webview: vscode.Webview): string {
    // Same pattern as panel webview
    return '...';
  }
}

// In activate():
context.subscriptions.push(
  vscode.window.registerWebviewViewProvider(
    MyWebviewViewProvider.viewType,
    new MyWebviewViewProvider(context.extensionUri)
  )
);
```

Register in package.json under `contributes.views` pointing to a `viewsContainers` entry.

---

## Terminal API

### Creating and Managing Terminals

```typescript
// Create a terminal
const terminal = vscode.window.createTerminal({
  name: 'My Terminal',
  cwd: '/some/directory',
  env: { MY_VAR: 'value' }
});

terminal.show();                    // focus this terminal
terminal.sendText('echo hello');    // execute a command
terminal.sendText('exit', true);    // send text + Enter

// Get process info
const pid = await terminal.processId;
```

### Enumerating and Finding Terminals

```typescript
// All open terminals
const allTerminals = vscode.window.terminals;

// Currently focused terminal
const active = vscode.window.activeTerminal;

// Find by name
const myTerm = vscode.window.terminals.find(t => t.name === 'My Terminal');
```

### Terminal Events

```typescript
// New terminal opened
vscode.window.onDidOpenTerminal(terminal => {
  console.log(`Opened: ${terminal.name}`);
});

// Terminal closed
vscode.window.onDidCloseTerminal(terminal => {
  console.log(`Closed: ${terminal.name}, exit: ${terminal.exitStatus?.code}`);
});

// Active terminal changed
vscode.window.onDidChangeActiveTerminal(terminal => {
  console.log(`Active: ${terminal?.name}`);
});

// Shell integration became available
vscode.window.onDidChangeTerminalShellIntegration(({ terminal, shellIntegration }) => {
  // Shell integration provides command detection, cwd tracking, etc.
});
```

### Terminal.show() Behavior

`terminal.show()` handles both tab selection and split-pane focus — a single call is sufficient
to bring any terminal into view regardless of its layout position.

---

## FileSystemWatcher

### Watching Files

```typescript
// Watch specific pattern in a folder
const watcher = vscode.workspace.createFileSystemWatcher(
  new vscode.RelativePattern(someFolder, '**/*.json')
);

watcher.onDidChange(uri => {
  console.log(`Changed: ${uri.fsPath}`);
});

watcher.onDidCreate(uri => {
  console.log(`Created: ${uri.fsPath}`);
});

watcher.onDidDelete(uri => {
  console.log(`Deleted: ${uri.fsPath}`);
});

context.subscriptions.push(watcher);
```

### Watching Outside the Workspace

```typescript
// For files outside workspace folders, use an absolute glob
const watcher = vscode.workspace.createFileSystemWatcher(
  new vscode.RelativePattern(
    vscode.Uri.file('/home/user/.config/myapp'),
    '*.json'
  )
);
```

### Why VS Code's Watcher Over Node.js fs.watch

The VS Code FileSystemWatcher runs outside the editor process and uses the OS's native file
notification system (inotify on Linux, FSEvents on macOS, ReadDirectoryChangesW on Windows).
This is more efficient and reliable than Node.js `fs.watch()`, which has known cross-platform
inconsistencies. Always prefer the VS Code API in extensions.

---

## Status Bar

```typescript
const statusBarItem = vscode.window.createStatusBarItem(
  vscode.StatusBarAlignment.Left,  // or Right
  100                               // priority (higher = further left)
);

statusBarItem.text = '$(sync~spin) Syncing...';   // codicon + text
statusBarItem.tooltip = 'Click to stop syncing';
statusBarItem.command = 'myExt.stopSync';
statusBarItem.color = new vscode.ThemeColor('statusBarItem.warningForeground');
statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
statusBarItem.show();

context.subscriptions.push(statusBarItem);
```

Animated icons: append `~spin` to a codicon name (e.g., `$(sync~spin)`) for a spinning animation.

---

## Commands

```typescript
// Register a command
const cmd = vscode.commands.registerCommand('myExt.doSomething', (arg1, arg2) => {
  // Handler receives arguments passed from menus, tree items, etc.
});

// Execute a command programmatically
await vscode.commands.executeCommand('vscode.open', uri);
await vscode.commands.executeCommand('myExt.doSomething', 'hello', 42);

// Register a text-editor-specific command (receives TextEditor and Edit)
vscode.commands.registerTextEditorCommand('myExt.format', (editor, edit) => {
  // Has access to the active editor
});
```

---

## Configuration

### Reading Settings

```typescript
const config = vscode.workspace.getConfiguration('myExt');
const interval = config.get<number>('refreshInterval', 3000);
const enabled = config.get<boolean>('enabled', true);
```

### Watching for Setting Changes

```typescript
vscode.workspace.onDidChangeConfiguration(e => {
  if (e.affectsConfiguration('myExt.refreshInterval')) {
    const newInterval = vscode.workspace.getConfiguration('myExt')
      .get<number>('refreshInterval', 3000);
    // React to the change
  }
});
```

### Updating Settings

```typescript
await vscode.workspace.getConfiguration('myExt')
  .update('refreshInterval', 5000, vscode.ConfigurationTarget.Global);
```

---

## Disposable Pattern

Every resource that listens to events or holds references should be disposable:

```typescript
export function activate(context: vscode.ExtensionContext) {
  // Push everything to subscriptions for automatic cleanup
  context.subscriptions.push(
    vscode.commands.registerCommand('myExt.cmd', handler),
    vscode.window.createTreeView('myView', { treeDataProvider: provider }),
    vscode.workspace.createFileSystemWatcher('**/*.json'),
    statusBarItem,
    someInterval  // if you wrap setInterval: { dispose: () => clearInterval(id) }
  );
}
```

For custom disposables wrapping timers or other resources:

```typescript
function createInterval(callback: () => void, ms: number): vscode.Disposable {
  const id = setInterval(callback, ms);
  return { dispose: () => clearInterval(id) };
}
```
