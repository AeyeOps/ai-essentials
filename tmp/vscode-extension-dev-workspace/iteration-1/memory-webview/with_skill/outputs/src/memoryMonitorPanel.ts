import * as vscode from 'vscode';
import * as os from 'os';
import { getWebviewContent } from './webviewContent';

interface MemorySnapshot {
  timestamp: number;
  totalMB: number;
  usedMB: number;
  freeMB: number;
  usedPercent: number;
}

interface WebviewState {
  snapshots: MemorySnapshot[];
  isPaused: boolean;
}

export class MemoryMonitorPanel {
  public static readonly viewType = 'memoryMonitor';

  private static instance: MemoryMonitorPanel | undefined;

  private readonly panel: vscode.WebviewPanel;
  private readonly extensionUri: vscode.Uri;
  private pollTimer: ReturnType<typeof setInterval> | undefined;
  private disposables: vscode.Disposable[] = [];
  private isPaused = false;

  private constructor(
    panel: vscode.WebviewPanel,
    context: vscode.ExtensionContext,
    restoredState?: unknown
  ) {
    this.panel = panel;
    this.extensionUri = context.extensionUri;

    this.panel.iconPath = new vscode.ThemeIcon('dashboard');
    this.setupWebview();
    this.setupMessageHandling(context);
    this.setupLifecycle();

    if (restoredState && typeof restoredState === 'object') {
      const state = restoredState as Partial<WebviewState>;
      if (state.isPaused) {
        this.isPaused = true;
      }
    }

    this.startPolling();
  }

  public static createOrShow(context: vscode.ExtensionContext): void {
    if (MemoryMonitorPanel.instance) {
      MemoryMonitorPanel.instance.panel.reveal(vscode.ViewColumn.Beside);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      MemoryMonitorPanel.viewType,
      'Memory Monitor',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        localResourceRoots: [
          vscode.Uri.joinPath(context.extensionUri, 'media')
        ],
        retainContextWhenHidden: true
      }
    );

    MemoryMonitorPanel.instance = new MemoryMonitorPanel(panel, context);
  }

  public static revive(
    panel: vscode.WebviewPanel,
    context: vscode.ExtensionContext,
    state: unknown
  ): void {
    MemoryMonitorPanel.instance = new MemoryMonitorPanel(panel, context, state);
  }

  private setupWebview(): void {
    this.panel.webview.html = getWebviewContent(
      this.panel.webview,
      this.extensionUri
    );
  }

  private setupMessageHandling(context: vscode.ExtensionContext): void {
    this.panel.webview.onDidReceiveMessage(
      (message: { type: string }) => {
        switch (message.type) {
          case 'ready':
            this.sendSnapshot();
            break;
          case 'pause':
            this.isPaused = true;
            this.stopPolling();
            break;
          case 'resume':
            this.isPaused = false;
            this.startPolling();
            break;
          case 'clear':
            break;
          case 'requestSnapshot':
            this.sendSnapshot();
            break;
        }
      },
      undefined,
      context.subscriptions
    );
  }

  private setupLifecycle(): void {
    this.panel.onDidChangeViewState(
      (e) => {
        if (e.webviewPanel.visible && !this.isPaused) {
          this.startPolling();
        } else if (!e.webviewPanel.visible) {
          this.stopPolling();
        }
      },
      null,
      this.disposables
    );

    this.panel.onDidDispose(
      () => {
        this.stopPolling();
        MemoryMonitorPanel.instance = undefined;
        for (const d of this.disposables) {
          d.dispose();
        }
      },
      null,
      this.disposables
    );

    const configDisposable = vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('memoryMonitor.pollInterval')) {
        if (!this.isPaused) {
          this.stopPolling();
          this.startPolling();
        }
      }
      if (e.affectsConfiguration('memoryMonitor.maxDataPoints')) {
        const config = vscode.workspace.getConfiguration('memoryMonitor');
        const maxDataPoints = config.get<number>('maxDataPoints', 60);
        this.panel.webview.postMessage({
          type: 'configUpdate',
          maxDataPoints
        });
      }
    });
    this.disposables.push(configDisposable);
  }

  private startPolling(): void {
    if (this.pollTimer) {
      return;
    }
    const config = vscode.workspace.getConfiguration('memoryMonitor');
    const interval = config.get<number>('pollInterval', 2000);

    this.pollTimer = setInterval(() => {
      this.sendSnapshot();
    }, interval);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  private sendSnapshot(): void {
    const totalBytes = os.totalmem();
    const freeBytes = os.freemem();
    const usedBytes = totalBytes - freeBytes;

    const snapshot: MemorySnapshot = {
      timestamp: Date.now(),
      totalMB: Math.round(totalBytes / (1024 * 1024)),
      usedMB: Math.round(usedBytes / (1024 * 1024)),
      freeMB: Math.round(freeBytes / (1024 * 1024)),
      usedPercent: Math.round((usedBytes / totalBytes) * 1000) / 10
    };

    this.panel.webview.postMessage({ type: 'snapshot', data: snapshot });
  }
}
