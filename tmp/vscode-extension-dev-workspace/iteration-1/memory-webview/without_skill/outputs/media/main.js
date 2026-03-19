(function () {
  // @ts-check
  'use strict';

  /** @type {typeof acquireVsCodeApi} */
  const vscode = acquireVsCodeApi();

  const MAX_DATA_POINTS = 60;

  /** @type {Array<{timestamp: number, totalMB: number, usedMB: number, freeMB: number, usedPercent: number}>} */
  let history = [];

  const totalMemoryEl = document.getElementById('totalMemory');
  const usedMemoryEl = document.getElementById('usedMemory');
  const freeMemoryEl = document.getElementById('freeMemory');
  const usagePercentEl = document.getElementById('usagePercent');
  const memoryChartCanvas = /** @type {HTMLCanvasElement} */ (document.getElementById('memoryChart'));
  const percentChartCanvas = /** @type {HTMLCanvasElement} */ (document.getElementById('percentChart'));

  const memoryCtx = memoryChartCanvas.getContext('2d');
  const percentCtx = percentChartCanvas.getContext('2d');

  function getThemeColors() {
    const style = getComputedStyle(document.body);
    return {
      foreground: style.getPropertyValue('--vscode-foreground').trim() || '#cccccc',
      background: style.getPropertyValue('--vscode-editor-background').trim() || '#1e1e1e',
      blue: style.getPropertyValue('--vscode-charts-blue').trim() || '#3794ff',
      green: style.getPropertyValue('--vscode-charts-green').trim() || '#89d185',
      red: style.getPropertyValue('--vscode-charts-red').trim() || '#f14c4c',
      yellow: style.getPropertyValue('--vscode-charts-yellow').trim() || '#cca700',
      gridColor: style.getPropertyValue('--vscode-panel-border').trim() || 'rgba(128, 128, 128, 0.35)',
      descriptionForeground: style.getPropertyValue('--vscode-descriptionForeground').trim() || 'rgba(204, 204, 204, 0.7)',
    };
  }

  function formatMB(mb) {
    if (mb >= 1024) {
      return (mb / 1024).toFixed(1) + ' GB';
    }
    return mb + ' MB';
  }

  function formatTime(timestamp) {
    const d = new Date(timestamp);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function setupCanvas(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    return { width: rect.width, height: rect.height };
  }

  function drawMemoryChart() {
    if (!memoryCtx || history.length < 2) return;

    const { width, height } = setupCanvas(memoryChartCanvas);
    const colors = getThemeColors();

    const padding = { top: 10, right: 60, bottom: 30, left: 60 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    memoryCtx.clearRect(0, 0, width, height);

    const maxTotal = history.length > 0 ? history[0].totalMB : 1;

    memoryCtx.strokeStyle = colors.gridColor;
    memoryCtx.lineWidth = 0.5;
    memoryCtx.font = '10px ' + getComputedStyle(document.body).fontFamily;
    memoryCtx.fillStyle = colors.descriptionForeground;

    const gridLines = 5;
    for (let i = 0; i <= gridLines; i++) {
      const y = padding.top + (chartHeight / gridLines) * i;
      const value = maxTotal - (maxTotal / gridLines) * i;

      memoryCtx.beginPath();
      memoryCtx.moveTo(padding.left, y);
      memoryCtx.lineTo(width - padding.right, y);
      memoryCtx.stroke();

      memoryCtx.textAlign = 'right';
      memoryCtx.textBaseline = 'middle';
      memoryCtx.fillText(formatMB(Math.round(value)), padding.left - 8, y);
    }

    const timeStep = Math.max(1, Math.floor(history.length / 5));
    for (let i = 0; i < history.length; i += timeStep) {
      const x = padding.left + (i / (MAX_DATA_POINTS - 1)) * chartWidth;
      memoryCtx.textAlign = 'center';
      memoryCtx.textBaseline = 'top';
      memoryCtx.fillText(formatTime(history[i].timestamp), x, height - padding.bottom + 8);
    }

    function drawArea(dataKey, color, alpha) {
      memoryCtx.beginPath();
      memoryCtx.moveTo(padding.left, padding.top + chartHeight);

      for (let i = 0; i < history.length; i++) {
        const x = padding.left + (i / (MAX_DATA_POINTS - 1)) * chartWidth;
        const val = history[i][dataKey];
        const y = padding.top + chartHeight - (val / maxTotal) * chartHeight;

        if (i === 0) {
          memoryCtx.lineTo(x, y);
        } else {
          memoryCtx.lineTo(x, y);
        }
      }

      const lastX = padding.left + ((history.length - 1) / (MAX_DATA_POINTS - 1)) * chartWidth;
      memoryCtx.lineTo(lastX, padding.top + chartHeight);
      memoryCtx.closePath();

      memoryCtx.fillStyle = hexToRgba(color, alpha);
      memoryCtx.fill();

      memoryCtx.beginPath();
      for (let i = 0; i < history.length; i++) {
        const x = padding.left + (i / (MAX_DATA_POINTS - 1)) * chartWidth;
        const val = history[i][dataKey];
        const y = padding.top + chartHeight - (val / maxTotal) * chartHeight;

        if (i === 0) {
          memoryCtx.moveTo(x, y);
        } else {
          memoryCtx.lineTo(x, y);
        }
      }
      memoryCtx.strokeStyle = color;
      memoryCtx.lineWidth = 2;
      memoryCtx.stroke();
    }

    drawArea('usedMB', colors.blue, 0.3);
    drawArea('freeMB', colors.green, 0.15);
  }

  function drawPercentChart() {
    if (!percentCtx || history.length < 2) return;

    const { width, height } = setupCanvas(percentChartCanvas);
    const colors = getThemeColors();

    const padding = { top: 10, right: 60, bottom: 30, left: 60 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    percentCtx.clearRect(0, 0, width, height);

    percentCtx.strokeStyle = colors.gridColor;
    percentCtx.lineWidth = 0.5;
    percentCtx.font = '10px ' + getComputedStyle(document.body).fontFamily;
    percentCtx.fillStyle = colors.descriptionForeground;

    const gridValues = [0, 25, 50, 75, 100];
    for (const val of gridValues) {
      const y = padding.top + chartHeight - (val / 100) * chartHeight;

      percentCtx.beginPath();
      percentCtx.moveTo(padding.left, y);
      percentCtx.lineTo(width - padding.right, y);
      percentCtx.stroke();

      percentCtx.textAlign = 'right';
      percentCtx.textBaseline = 'middle';
      percentCtx.fillText(val + '%', padding.left - 8, y);
    }

    // Warning threshold line at 80%
    const warningY = padding.top + chartHeight - (80 / 100) * chartHeight;
    percentCtx.beginPath();
    percentCtx.setLineDash([5, 5]);
    percentCtx.strokeStyle = colors.yellow;
    percentCtx.lineWidth = 1;
    percentCtx.moveTo(padding.left, warningY);
    percentCtx.lineTo(width - padding.right, warningY);
    percentCtx.stroke();
    percentCtx.setLineDash([]);

    // Critical threshold line at 95%
    const criticalY = padding.top + chartHeight - (95 / 100) * chartHeight;
    percentCtx.beginPath();
    percentCtx.setLineDash([5, 5]);
    percentCtx.strokeStyle = colors.red;
    percentCtx.lineWidth = 1;
    percentCtx.moveTo(padding.left, criticalY);
    percentCtx.lineTo(width - padding.right, criticalY);
    percentCtx.stroke();
    percentCtx.setLineDash([]);

    percentCtx.textAlign = 'left';
    percentCtx.fillStyle = colors.yellow;
    percentCtx.fillText('Warning 80%', width - padding.right + 4, warningY);
    percentCtx.fillStyle = colors.red;
    percentCtx.fillText('Critical 95%', width - padding.right + 4, criticalY);

    percentCtx.beginPath();
    for (let i = 0; i < history.length; i++) {
      const x = padding.left + (i / (MAX_DATA_POINTS - 1)) * chartWidth;
      const y = padding.top + chartHeight - (history[i].usedPercent / 100) * chartHeight;

      if (i === 0) {
        percentCtx.moveTo(x, y);
      } else {
        percentCtx.lineTo(x, y);
      }
    }

    const lastPercent = history[history.length - 1].usedPercent;
    let lineColor = colors.blue;
    if (lastPercent >= 95) {
      lineColor = colors.red;
    } else if (lastPercent >= 80) {
      lineColor = colors.yellow;
    }

    percentCtx.strokeStyle = lineColor;
    percentCtx.lineWidth = 2.5;
    percentCtx.stroke();

    const lastX = padding.left + ((history.length - 1) / (MAX_DATA_POINTS - 1)) * chartWidth;
    const lastY = padding.top + chartHeight - (lastPercent / 100) * chartHeight;
    percentCtx.beginPath();
    percentCtx.arc(lastX, lastY, 4, 0, Math.PI * 2);
    percentCtx.fillStyle = lineColor;
    percentCtx.fill();
  }

  function hexToRgba(hex, alpha) {
    hex = hex.replace('#', '');
    if (hex.length === 3) {
      hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    }
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function updateStats(data) {
    if (totalMemoryEl) totalMemoryEl.textContent = formatMB(data.totalMB);
    if (usedMemoryEl) usedMemoryEl.textContent = formatMB(data.usedMB);
    if (freeMemoryEl) freeMemoryEl.textContent = formatMB(data.freeMB);
    if (usagePercentEl) usagePercentEl.textContent = data.usedPercent.toFixed(1) + '%';
  }

  function persistState() {
    const state = { history: history, maxDataPoints: MAX_DATA_POINTS };
    vscode.setState(state);
    vscode.postMessage({ command: 'saveState', state: state });
  }

  window.addEventListener('message', function (event) {
    const message = event.data;

    switch (message.command) {
      case 'memoryUpdate': {
        const data = message.data;
        history.push(data);
        if (history.length > MAX_DATA_POINTS) {
          history = history.slice(-MAX_DATA_POINTS);
        }
        updateStats(data);
        drawMemoryChart();
        drawPercentChart();
        persistState();
        break;
      }
      case 'restoreState': {
        if (message.state && message.state.history) {
          history = message.state.history;
          if (history.length > 0) {
            updateStats(history[history.length - 1]);
            drawMemoryChart();
            drawPercentChart();
          }
        }
        break;
      }
    }
  });

  window.addEventListener('resize', function () {
    drawMemoryChart();
    drawPercentChart();
  });

  const previousState = vscode.getState();
  if (previousState && previousState.history) {
    history = previousState.history;
    if (history.length > 0) {
      updateStats(history[history.length - 1]);
      drawMemoryChart();
      drawPercentChart();
    }
  }

  vscode.postMessage({ command: 'ready' });
})();
