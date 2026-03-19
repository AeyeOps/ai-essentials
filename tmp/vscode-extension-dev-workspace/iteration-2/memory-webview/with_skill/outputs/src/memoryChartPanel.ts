import * as vscode from 'vscode';
import * as os from 'os';

interface MemorySnapshot {
  timestamp: number;
  totalMB: number;
  usedMB: number;
  freeMB: number;
  usedPercent: number;
}

interface WebviewState {
  dataPoints: MemorySnapshot[];
}

export class MemoryChartPanel {
  private static instance: MemoryChartPanel | undefined;

  private readonly panel: vscode.WebviewPanel;
  private readonly extensionUri: vscode.Uri;
  private timer: NodeJS.Timeout | undefined;
  private dataPoints: MemorySnapshot[] = [];
  private disposed = false;

  private constructor(
    panel: vscode.WebviewPanel,
    context: vscode.ExtensionContext,
    existingState?: unknown
  ) {
    this.panel = panel;
    this.extensionUri = context.extensionUri;

    if (existingState && typeof existingState === 'object' && existingState !== null) {
      const state = existingState as WebviewState;
      if (Array.isArray(state.dataPoints)) {
        this.dataPoints = state.dataPoints;
      }
    }

    this.panel.iconPath = new vscode.ThemeIcon('pulse');
    this.panel.webview.options = {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, 'media')]
    };
    this.panel.webview.html = this.getHtml();

    this.panel.webview.onDidReceiveMessage(
      (message: { type: string }) => {
        if (message.type === 'ready') {
          if (this.dataPoints.length > 0) {
            this.panel.webview.postMessage({
              type: 'restore',
              dataPoints: this.dataPoints
            });
          }
          this.startPolling();
        }
      },
      undefined,
      context.subscriptions
    );

    this.panel.onDidChangeViewState(
      () => {
        if (this.panel.visible) {
          this.startPolling();
        } else {
          this.stopPolling();
        }
      },
      undefined,
      context.subscriptions
    );

    this.panel.onDidDispose(() => {
      this.dispose();
    }, null, context.subscriptions);

    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('memoryChart.pollInterval') ||
          e.affectsConfiguration('memoryChart.maxDataPoints')) {
        this.stopPolling();
        this.startPolling();
      }
    }, undefined, context.subscriptions);
  }

  static createOrShow(context: vscode.ExtensionContext): void {
    if (MemoryChartPanel.instance) {
      MemoryChartPanel.instance.panel.reveal(vscode.ViewColumn.One);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      'memoryChart',
      'Memory Chart',
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]
      }
    );

    MemoryChartPanel.instance = new MemoryChartPanel(panel, context);
  }

  static restore(
    panel: vscode.WebviewPanel,
    context: vscode.ExtensionContext,
    state: unknown
  ): void {
    MemoryChartPanel.instance = new MemoryChartPanel(panel, context, state);
  }

  private getConfig() {
    const config = vscode.workspace.getConfiguration('memoryChart');
    return {
      pollInterval: config.get<number>('pollInterval', 2000),
      maxDataPoints: config.get<number>('maxDataPoints', 60)
    };
  }

  private sampleMemory(): MemorySnapshot {
    const totalBytes = os.totalmem();
    const freeBytes = os.freemem();
    const usedBytes = totalBytes - freeBytes;
    const totalMB = Math.round(totalBytes / (1024 * 1024));
    const usedMB = Math.round(usedBytes / (1024 * 1024));
    const freeMB = Math.round(freeBytes / (1024 * 1024));
    const usedPercent = Math.round((usedBytes / totalBytes) * 10000) / 100;

    return {
      timestamp: Date.now(),
      totalMB,
      usedMB,
      freeMB,
      usedPercent
    };
  }

  private startPolling(): void {
    if (this.timer || this.disposed) {
      return;
    }

    const { pollInterval, maxDataPoints } = this.getConfig();

    const tick = () => {
      const snapshot = this.sampleMemory();
      this.dataPoints.push(snapshot);
      if (this.dataPoints.length > maxDataPoints) {
        this.dataPoints = this.dataPoints.slice(-maxDataPoints);
      }
      this.panel.webview.postMessage({ type: 'update', snapshot });
    };

    tick();
    this.timer = setInterval(tick, pollInterval);
  }

  private stopPolling(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  private dispose(): void {
    this.disposed = true;
    this.stopPolling();
    MemoryChartPanel.instance = undefined;
  }

  private getHtml(): string {
    const webview = this.panel.webview;

    const scriptUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, 'media', 'main.js')
    );
    const styleUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, 'media', 'style.css')
    );
    const nonce = getNonce();

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy"
    content="default-src 'none';
      style-src ${webview.cspSource};
      script-src 'nonce-${nonce}';
      img-src ${webview.cspSource} https:;
      font-src ${webview.cspSource};">
  <link href="${styleUri}" rel="stylesheet">
  <title>Memory Chart</title>
</head>
<body>
  <div id="header">
    <h2>System Memory Usage</h2>
    <div id="stats">
      <span id="stat-used" class="stat-badge">Used: --</span>
      <span id="stat-free" class="stat-badge">Free: --</span>
      <span id="stat-total" class="stat-badge">Total: --</span>
      <span id="stat-percent" class="stat-badge">-- %</span>
    </div>
  </div>
  <div id="chart-container">
    <canvas id="chart"></canvas>
  </div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
  }
}

function getNonce(): string {
  let text = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return text;
}
