import * as vscode from 'vscode';

export function getWebviewContent(
  webview: vscode.Webview,
  extensionUri: vscode.Uri
): string {
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
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy"
    content="default-src 'none';
      style-src ${webview.cspSource};
      script-src 'nonce-${nonce}';
      img-src ${webview.cspSource} data:;
      font-src ${webview.cspSource};">
  <link href="${styleUri}" rel="stylesheet">
  <title>Memory Monitor</title>
</head>
<body>
  <div id="header">
    <h2>System Memory Usage</h2>
    <div id="controls">
      <button id="pauseBtn" title="Pause polling">Pause</button>
      <button id="clearBtn" title="Clear history">Clear</button>
    </div>
  </div>
  <div id="stats">
    <div class="stat-card">
      <span class="stat-label">Used</span>
      <span class="stat-value" id="usedValue">--</span>
    </div>
    <div class="stat-card">
      <span class="stat-label">Free</span>
      <span class="stat-value" id="freeValue">--</span>
    </div>
    <div class="stat-card">
      <span class="stat-label">Total</span>
      <span class="stat-value" id="totalValue">--</span>
    </div>
    <div class="stat-card">
      <span class="stat-label">Usage</span>
      <span class="stat-value" id="percentValue">--</span>
    </div>
  </div>
  <div id="chart-container">
    <canvas id="chart"></canvas>
  </div>
  <div id="chart-legend">
    <span class="legend-item"><span class="legend-color legend-used"></span> Used MB</span>
    <span class="legend-item"><span class="legend-color legend-free"></span> Free MB</span>
  </div>
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
