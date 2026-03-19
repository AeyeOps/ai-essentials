---
name: vscode-extension-dev
description: >
  Contains verified esbuild configurations, WSL/code-insiders workflow requirements, and
  package.json contributes patterns for VS Code extension development that produce more correct
  results than reasoning from general training alone. This environment requires code-insiders
  (not code) for all CLI operations — the skill enforces this constraint and provides tested
  scaffolding, build scripts, and publish workflows that work under WSL. Covers TreeDataProvider,
  WebviewPanel/WebviewViewProvider with state persistence, FileSystemWatcher, StatusBarItem,
  command registration, menu when-clauses, activation events, esbuild bundling with
  problem-matcher plugin, @vscode/test-cli test runner, and vsce publishing. Consult when
  building a VS Code extension, scaffolding an extension project, implementing extension APIs
  (TreeView, Webview, sidebar panels, context menus, status bar), configuring package.json
  contribution points, setting up extension tests, bundling with esbuild, or publishing to the
  marketplace. Do NOT use for configuring VS Code as a user (themes, settings, keybindings,
  tasks.json), Chrome/browser extensions, Electron apps, JupyterLab plugins, or Monaco Editor
  embeds.
---

# VS Code Extension Development

Comprehensive guide for building VS Code extensions from scratch through publication.

## Code Insiders Requirement

This environment uses **VS Code Insiders** (`code-insiders`), not the stable `code` command.
Every CLI invocation, launch config, README instruction, and documentation reference in the
extension project must use `code-insiders`. This matters because the development workflow runs
under WSL where only the Insiders build is available. Specifically:

- Installation commands: `code-insiders --install-extension my-ext.vsix`
- Launch instructions in README: "Open with `code-insiders .`"
- Any shell scripts or npm scripts that invoke VS Code: use `code-insiders`
- The `.vscode/launch.json` `runtimeExecutable` should use `${execPath}` (which resolves
  correctly), but any documentation or comments should reference code-insiders

If the user says "VS Code" or "code", they mean code-insiders. Never generate `code` commands
without the `-insiders` suffix.

## Quick Start — Scaffold a New Extension

Generate a TypeScript extension project:

```bash
npx --package yo --package generator-code -- yo code
```

Select "New Extension (TypeScript)" when prompted. This creates a ready-to-run project with
`src/extension.ts`, `package.json`, and TypeScript configuration.

Open the project and launch the Extension Development Host with F5 to test immediately.

After scaffolding, convert the build system from tsc to esbuild — see the esbuild section below.
The yo generator creates a tsc-based build by default, but esbuild bundles are smaller, faster,
and what VS Code itself uses internally (as of v1.110).

## Project Structure

```
extension-name/
  package.json            # manifest: contribution points, activation, settings
  esbuild.js              # build script (replaces default tsc pipeline)
  tsconfig.json           # TypeScript config
  .vscodeignore           # files excluded from .vsix package
  .vscode-test.mjs        # test runner configuration
  src/
    extension.ts          # activate() / deactivate() entry point
    *.ts                  # feature modules
  dist/
    extension.js          # bundled output (single file)
```

Keep `src/` organized by feature. Each major capability (a TreeView provider, a webview, a
command group) gets its own module file. The `extension.ts` entry point wires them together
in `activate()` and tears them down in `deactivate()`.

## package.json — The Extension Manifest

The manifest declares everything the extension contributes to VS Code. Key fields:

```jsonc
{
  "name": "my-extension",
  "displayName": "My Extension",
  "version": "0.1.0",
  "engines": { "vscode": "^1.110.0" },   // caret = forward-compatible
  "main": "./dist/extension",             // points to esbuild output
  "activationEvents": [],                 // usually auto-inferred
  "contributes": { /* see below */ }
}
```

### Activation Events

VS Code auto-generates activation events for most contribution points — you rarely need to
declare them manually. Notable exceptions:

- `onWebviewPanel:viewType` — for webview panel restoration
- `onUri` — for URI handlers
- `*` — activate on startup (avoid unless truly needed)

For views (`contributes.views`), VS Code automatically activates on `onView:viewId`.

### Contribution Points

The `contributes` object declares UI elements, commands, settings, and more:

```jsonc
{
  "contributes": {
    // Commands the extension provides
    "commands": [{
      "command": "myExt.refresh",
      "title": "Refresh",
      "icon": "$(refresh)",              // codicon reference
      "category": "My Extension"
    }],

    // Views in the sidebar, panel, or built-in containers
    "views": {
      "explorer": [{                     // built-in container
        "id": "myView",
        "name": "My View"
      }]
    },

    // Custom view containers (activity bar or panel)
    "viewsContainers": {
      "activitybar": [{
        "id": "myContainer",
        "title": "My Container",
        "icon": "media/icon.svg"
      }],
      "panel": [{
        "id": "myPanel",
        "title": "My Panel",
        "icon": "media/icon.svg"
      }]
    },

    // Toolbar and context menu placement
    "menus": {
      "view/title": [{                   // toolbar at top of view
        "command": "myExt.refresh",
        "when": "view == myView",
        "group": "navigation"            // shows as icon, not menu item
      }],
      "view/item/context": [{            // right-click on tree items
        "command": "myExt.openItem",
        "when": "view == myView && viewItem == editable",
        "group": "inline"                // inline icon on the row
      }]
    },

    // Welcome content for empty views
    "viewsWelcome": [{
      "view": "myView",
      "contents": "No items found.\n[Get Started](command:myExt.init)"
    }],

    // User-configurable settings
    "configuration": {
      "title": "My Extension",
      "properties": {
        "myExt.refreshInterval": {
          "type": "number",
          "default": 3000,
          "description": "Refresh interval in milliseconds"
        }
      }
    }
  }
}
```

### Menu `when` Clauses

Control visibility with boolean expressions:
- `view == myView` — only in a specific view
- `viewItem == someContext` — only for tree items with that `contextValue`
- `resourceScheme == file` — only for file URIs
- Combine with `&&`, `||`, `!`

### Menu Group Ordering

Use `@` suffix for ordering within a group: `"navigation@1"`, `"navigation@2"`.

## Extension Entry Point

```typescript
import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
  // Register commands, providers, watchers here
  // Push disposables to context.subscriptions for cleanup

  const disposable = vscode.commands.registerCommand('myExt.hello', () => {
    vscode.window.showInformationMessage('Hello!');
  });

  context.subscriptions.push(disposable);
}

export function deactivate() {
  // Cleanup if needed (most things auto-dispose via subscriptions)
}
```

Every disposable (commands, watchers, providers, views) should be pushed to
`context.subscriptions` so VS Code cleans them up on deactivation.

## Core API Patterns

This section covers the most common patterns. For detailed API reference with full code examples,
read `references/api-patterns.md`.

### TreeView

The most common way to add structured data to the sidebar or panel:

1. Implement `TreeDataProvider<T>` with `getChildren()` and `getTreeItem()`
2. Fire `onDidChangeTreeData` to refresh
3. Register via `vscode.window.createTreeView()` for full API access

TreeItems support labels, descriptions, tooltips, icons (ThemeIcon or custom SVG), collapsible
state, contextValue (for menu filtering), and a command to execute on click.

### Webview

For custom HTML/CSS/JS interfaces when TreeView isn't sufficient:

1. Create with `vscode.window.createWebviewPanel()` or implement `WebviewViewProvider`
2. Set HTML content, load local resources via `webview.asWebviewUri()`
3. Communicate via `postMessage()` / `onDidReceiveMessage()`
4. Always set a Content Security Policy

Webviews are sandboxed — they cannot access the filesystem directly. All communication goes
through the message passing API.

### Terminal

For interacting with VS Code's integrated terminal:

- `window.createTerminal()` — create terminals
- `terminal.show()` — focus a terminal (handles tabs and split panes)
- `terminal.processId` — get the underlying PID
- `window.terminals` — enumerate all open terminals
- `onDidOpenTerminal` / `onDidCloseTerminal` — lifecycle events

### FileSystemWatcher

For reacting to file changes on disk. Prefer the VS Code API over Node.js `fs.watch()` because
it runs outside the editor process and uses efficient OS-level notifications (inotify on Linux):

```typescript
const watcher = vscode.workspace.createFileSystemWatcher(
  new vscode.RelativePattern(folder, '**/*.json')
);
watcher.onDidChange(uri => { /* file modified */ });
watcher.onDidCreate(uri => { /* file created */ });
watcher.onDidDelete(uri => { /* file deleted */ });
context.subscriptions.push(watcher);
```

### StatusBar

- `window.createStatusBarItem(alignment, priority)` — left or right alignment
- Convention: left side = workspace-scoped info, right side = file-scoped info
- Set `text`, `tooltip`, `command`, `color`, `backgroundColor`

## Building with esbuild

esbuild is the recommended bundler (VS Code's own built-in extensions switched to it in v1.110).
It produces a single `dist/extension.js` file from the TypeScript source.

### esbuild.js

```javascript
const esbuild = require('esbuild');

const production = process.argv.includes('--production');
const watch = process.argv.includes('--watch');

/** @type {import('esbuild').Plugin} */
const esbuildProblemMatcherPlugin = {
  name: 'esbuild-problem-matcher',
  setup(build) {
    build.onStart(() => { console.log('[watch] build started'); });
    build.onEnd(result => {
      for (const { text, location } of result.errors) {
        console.error(`✘ [ERROR] ${text}`);
        if (location) {
          console.error(`    ${location.file}:${location.line}:${location.column}:`);
        }
      }
      console.log('[watch] build finished');
    });
  },
};

async function main() {
  const ctx = await esbuild.context({
    entryPoints: ['src/extension.ts'],
    bundle: true,
    format: 'cjs',
    minify: production,
    sourcemap: !production,
    sourcesContent: false,
    platform: 'node',
    outfile: 'dist/extension.js',
    external: ['vscode'],
    logLevel: 'warning',
    plugins: [esbuildProblemMatcherPlugin],
  });
  if (watch) {
    await ctx.watch();
  } else {
    await ctx.rebuild();
    await ctx.dispose();
  }
}

main().catch(e => { console.error(e); process.exit(1); });
```

### npm Scripts

```json
{
  "scripts": {
    "compile": "npm run check-types && node esbuild.js",
    "check-types": "tsc --noEmit",
    "watch": "npm-run-all -p watch:*",
    "watch:esbuild": "node esbuild.js --watch",
    "watch:tsc": "tsc --noEmit --watch --project tsconfig.json",
    "package": "npm run check-types && node esbuild.js --production",
    "vscode:prepublish": "npm run package",
    "test": "vscode-test"
  }
}
```

The `watch` script runs esbuild and tsc in parallel — esbuild handles bundling while tsc
provides type checking. This gives sub-second rebuilds with full type safety.

`vscode:prepublish` runs automatically during `vsce package` and `vsce publish`.

### .vscodeignore

```
.vscode/
node_modules/
out/
src/
tsconfig.json
esbuild.js
.vscode-test.mjs
**/*.ts
!dist/**
```

Everything bundled into `dist/extension.js` can be excluded. This keeps the .vsix small.

## Testing

For testing setup, configuration, and debugging details, read `references/build-test-publish.md`.

Quick setup:

```bash
npm install --save-dev @vscode/test-cli @vscode/test-electron
```

Tests run inside an Extension Development Host with full VS Code API access. Configure in
`.vscode-test.mjs`:

```javascript
import { defineConfig } from '@vscode/test-cli';

export default defineConfig({
  files: 'out/test/**/*.test.js',
  mocha: { ui: 'tdd', timeout: 20000 }
});
```

Run: `npm test` or `npx vscode-test --label unitTests`

## Publishing

For full publishing workflow, read `references/build-test-publish.md`.

Quick reference:

```bash
npm install -g @vscode/vsce
vsce package                      # creates .vsix
vsce publish                      # publishes to marketplace
vsce publish minor                # auto-increment + publish
vsce publish --pre-release        # pre-release channel
code-insiders --install-extension my-ext-0.1.0.vsix   # local install
```

Platform-specific builds: `vsce package --target linux-x64 linux-arm64 darwin-x64`

## Platform Notes

### WSL

- Use `code-insiders` instead of `code` for all CLI operations — this is non-negotiable
- The Extension Host runs inside WSL — `~/.vscode-insiders/extensions/` is the Linux path
- No Windows path translation needed for extension code
- File watchers use inotify via VS Code's API (not Node.js fs.watch)
- In README install instructions, package.json scripts, and any user-facing docs: `code-insiders`

### Architecture Constraints

- Extensions run in the Extension Host process, separate from the VS Code UI
- No DOM access — you cannot manipulate VS Code's UI directly
- No custom CSS injection — use contribution points and the API
- Webviews are sandboxed with their own security context

## Reference Files

- `references/api-patterns.md` — Detailed API patterns with full code examples for TreeView,
  Webview, WebviewView, Terminal, FileSystemWatcher, and StatusBar. Read when implementing
  any of these APIs.
- `references/build-test-publish.md` — esbuild configuration rationale and additional options,
  TypeScript config, test runner setup, debugging tests, CI configuration, publishing workflow,
  and marketplace metadata. Read when setting up the build pipeline or preparing to publish.
