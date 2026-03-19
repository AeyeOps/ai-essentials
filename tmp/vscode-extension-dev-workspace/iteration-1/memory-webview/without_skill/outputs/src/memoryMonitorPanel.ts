import * as vscode from 'vscode';
import * as os from 'os';

interface MemorySnapshot {
  timestamp: number;
  totalMB: number;
  usedMB: number;
  freeMB: number;
  usedPercent: number;
}

interface WebviewMessage {
  command: 'requestData' | 'ready' | 'saveState';
  state?: PersistedState;
}

interface HostMessage {
  command: 'memoryUpdate' | 'restoreState';
  data?: MemorySnapshot;
  state?: PersistedState;
}

interface PersistedState {
  history: MemorySnapshot[];
  maxDataPoints: number;
}

export class MemoryMonitorPanel {
  public static currentPanel: MemoryMonitorPanel | undefined;
  public static readonly viewType = 'memoryMonitor';

  private readonly _panel: vscode.WebviewPanel;
  private readonly _extensionUri: vscode.Uri;
  private _disposables: vscode.Disposable[] = [];
  private _pollingInterval: ReturnType<typeof setInterval> | undefined;
  private _history: MemorySnapshot[] = [];
  private static readonly MAX_DATA_POINTS = 60;
  private static readonly POLL_INTERVAL_MS = 2000;

  public static createOrShow(extensionUri: vscode.Uri): void {
    const column = vscode.window.activeTextEditor
      ? vscode.window.activeTextEditor.viewColumn
      : undefined;

    if (MemoryMonitorPanel.currentPanel) {
      MemoryMonitorPanel.currentPanel._panel.reveal(column);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      MemoryMonitorPanel.viewType,
      'Memory Monitor',
      column || vscode.ViewColumn.One,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [
          vscode.Uri.joinPath(extensionUri, 'media'),
        ],
      }
    );

    MemoryMonitorPanel.currentPanel = new MemoryMonitorPanel(
      panel,
      extensionUri
    );
  }

  public static revive(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri
  ): void {
    MemoryMonitorPanel.currentPanel = new MemoryMonitorPanel(
      panel,
      extensionUri
    );
  }

  private constructor(
    panel: vscode.WebviewPanel,
    extensionUri: vscode.Uri
  ) {
    this._panel = panel;
    this._extensionUri = extensionUri;

    this._panel.webview.html = this._getHtmlForWebview(this._panel.webview);

    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);

    this._panel.webview.onDidReceiveMessage(
      (message: WebviewMessage) => {
        switch (message.command) {
          case 'ready':
            this._startPolling();
            if (this._history.length > 0) {
              const restoreMsg: HostMessage = {
                command: 'restoreState',
                state: {
                  history: this._history,
                  maxDataPoints: MemoryMonitorPanel.MAX_DATA_POINTS,
                },
              };
              void this._panel.webview.postMessage(restoreMsg);
            }
            break;
          case 'requestData':
            this._sendMemorySnapshot();
            break;
          case 'saveState':
            if (message.state) {
              this._history = message.state.history;
            }
            break;
        }
      },
      null,
      this._disposables
    );

    this._panel.onDidChangeViewState(
      () => {
        if (this._panel.visible) {
          this._startPolling();
        } else {
          this._stopPolling();
        }
      },
      null,
      this._disposables
    );
  }

  public dispose(): void {
    MemoryMonitorPanel.currentPanel = undefined;
    this._stopPolling();
    this._panel.dispose();

    while (this._disposables.length) {
      const disposable = this._disposables.pop();
      if (disposable) {
        disposable.dispose();
      }
    }
  }

  private _startPolling(): void {
    if (this._pollingInterval) {
      return;
    }
    this._sendMemorySnapshot();
    this._pollingInterval = setInterval(() => {
      this._sendMemorySnapshot();
    }, MemoryMonitorPanel.POLL_INTERVAL_MS);
  }

  private _stopPolling(): void {
    if (this._pollingInterval) {
      clearInterval(this._pollingInterval);
      this._pollingInterval = undefined;
    }
  }

  private _sendMemorySnapshot(): void {
    const totalBytes = os.totalmem();
    const freeBytes = os.freemem();
    const usedBytes = totalBytes - freeBytes;

    const snapshot: MemorySnapshot = {
      timestamp: Date.now(),
      totalMB: Math.round(totalBytes / (1024 * 1024)),
      usedMB: Math.round(usedBytes / (1024 * 1024)),
      freeMB: Math.round(freeBytes / (1024 * 1024)),
      usedPercent: Math.round((usedBytes / totalBytes) * 10000) / 100,
    };

    this._history.push(snapshot);
    if (this._history.length > MemoryMonitorPanel.MAX_DATA_POINTS) {
      this._history = this._history.slice(-MemoryMonitorPanel.MAX_DATA_POINTS);
    }

    const msg: HostMessage = {
      command: 'memoryUpdate',
      data: snapshot,
    };
    void this._panel.webview.postMessage(msg);
  }

  private _getHtmlForWebview(webview: vscode.Webview): string {
    const styleUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this._extensionUri, 'media', 'style.css')
    );
    const scriptUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this._extensionUri, 'media', 'main.js')
    );

    const nonce = getNonce();

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource} 'nonce-${nonce}'; script-src 'nonce-${nonce}'; font-src ${webview.cspSource};">
  <link href="${styleUri}" rel="stylesheet">
  <title>Memory Monitor</title>
</head>
<body>
  <div class="container">
    <header class="header">
      <h1>System Memory Monitor</h1>
      <div class="status-indicator" id="statusIndicator">
        <span class="pulse"></span>
        <span>Live</span>
      </div>
    </header>

    <div class="stats-row">
      <div class="stat-card">
        <div class="stat-label">Total Memory</div>
        <div class="stat-value" id="totalMemory">--</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Used Memory</div>
        <div class="stat-value" id="usedMemory">--</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Free Memory</div>
        <div class="stat-value" id="freeMemory">--</div>
      </div>
      <div class="stat-card highlight">
        <div class="stat-label">Usage</div>
        <div class="stat-value" id="usagePercent">--</div>
      </div>
    </div>

    <div class="chart-container">
      <div class="chart-header">
        <h2>Memory Usage Over Time</h2>
        <span class="chart-subtitle" id="chartSubtitle">Last 2 minutes (2s intervals)</span>
      </div>
      <canvas id="memoryChart" width="800" height="300"></canvas>
      <div class="chart-legend">
        <span class="legend-item"><span class="legend-color used"></span> Used</span>
        <span class="legend-item"><span class="legend-color free"></span> Free</span>
      </div>
    </div>

    <div class="chart-container">
      <div class="chart-header">
        <h2>Usage Percentage</h2>
      </div>
      <canvas id="percentChart" width="800" height="200"></canvas>
    </div>
  </div>

  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
  }
}

function getNonce(): string {
  let text = '';
  const possible =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}
