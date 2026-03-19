(function () {
  'use strict';

  const vscode = acquireVsCodeApi();

  const MAX_POINTS = 60;
  const WARN_THRESHOLD = 80;
  const CRITICAL_THRESHOLD = 95;

  let dataPoints = [];

  const canvas = document.getElementById('chart');
  const ctx = canvas.getContext('2d');
  const statUsed = document.getElementById('stat-used');
  const statFree = document.getElementById('stat-free');
  const statTotal = document.getElementById('stat-total');
  const statPercent = document.getElementById('stat-percent');

  let animationId = null;
  let dpr = window.devicePixelRatio || 1;

  function resizeCanvas() {
    const rect = canvas.parentElement.getBoundingClientRect();
    dpr = window.devicePixelRatio || 1;
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    canvas.style.width = rect.width + 'px';
    canvas.style.height = rect.height + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
  }

  function getChartColors() {
    const style = getComputedStyle(document.body);
    return {
      line: style.getPropertyValue('--chart-line').trim() || '#3794ff',
      fillStart: style.getPropertyValue('--chart-fill-start').trim() || 'rgba(55,148,255,0.3)',
      fillEnd: style.getPropertyValue('--chart-fill-end').trim() || 'rgba(55,148,255,0.02)',
      grid: style.getPropertyValue('--chart-grid').trim() || 'rgba(255,255,255,0.1)',
      label: style.getPropertyValue('--chart-label').trim() || 'rgba(255,255,255,0.5)',
      threshold: style.getPropertyValue('--chart-threshold').trim() || '#f14c4c'
    };
  }

  function formatMB(mb) {
    if (mb >= 1024) {
      return (mb / 1024).toFixed(1) + ' GB';
    }
    return mb + ' MB';
  }

  function formatTime(ts) {
    const d = new Date(ts);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    const s = d.getSeconds().toString().padStart(2, '0');
    return h + ':' + m + ':' + s;
  }

  function updateStats(snapshot) {
    statUsed.textContent = 'Used: ' + formatMB(snapshot.usedMB);
    statFree.textContent = 'Free: ' + formatMB(snapshot.freeMB);
    statTotal.textContent = 'Total: ' + formatMB(snapshot.totalMB);
    statPercent.textContent = snapshot.usedPercent.toFixed(1) + ' %';

    statPercent.classList.remove('warn', 'critical');
    if (snapshot.usedPercent >= CRITICAL_THRESHOLD) {
      statPercent.classList.add('critical');
    } else if (snapshot.usedPercent >= WARN_THRESHOLD) {
      statPercent.classList.add('warn');
    }
  }

  function draw() {
    if (!ctx) { return; }
    const rect = canvas.parentElement.getBoundingClientRect();
    const w = rect.width;
    const h = rect.height;

    ctx.clearRect(0, 0, w, h);

    if (dataPoints.length === 0) {
      ctx.fillStyle = getChartColors().label;
      ctx.font = '14px var(--vscode-font-family, sans-serif)';
      ctx.textAlign = 'center';
      ctx.fillText('Waiting for data...', w / 2, h / 2);
      return;
    }

    const colors = getChartColors();

    const padding = { top: 20, right: 20, bottom: 40, left: 60 };
    const chartW = w - padding.left - padding.right;
    const chartH = h - padding.top - padding.bottom;

    // Y axis: 0-100 percent
    const yMin = 0;
    const yMax = 100;

    // Grid lines
    ctx.strokeStyle = colors.grid;
    ctx.lineWidth = 0.5;
    ctx.setLineDash([4, 4]);

    const ySteps = [0, 25, 50, 75, 100];
    ctx.font = '11px var(--vscode-font-family, sans-serif)';
    ctx.fillStyle = colors.label;
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';

    for (const yVal of ySteps) {
      const y = padding.top + chartH - ((yVal - yMin) / (yMax - yMin)) * chartH;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(padding.left + chartW, y);
      ctx.stroke();
      ctx.fillText(yVal + '%', padding.left - 8, y);
    }

    // Threshold line at WARN_THRESHOLD
    ctx.strokeStyle = colors.threshold;
    ctx.lineWidth = 1;
    ctx.setLineDash([6, 3]);
    const thresholdY = padding.top + chartH - ((WARN_THRESHOLD - yMin) / (yMax - yMin)) * chartH;
    ctx.beginPath();
    ctx.moveTo(padding.left, thresholdY);
    ctx.lineTo(padding.left + chartW, thresholdY);
    ctx.stroke();
    ctx.setLineDash([]);

    // X axis time labels
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillStyle = colors.label;
    const labelCount = Math.min(dataPoints.length, 6);
    const labelStep = Math.max(1, Math.floor((dataPoints.length - 1) / (labelCount - 1)));
    for (let i = 0; i < dataPoints.length; i += labelStep) {
      const x = padding.left + (i / (Math.max(dataPoints.length - 1, 1))) * chartW;
      ctx.fillText(formatTime(dataPoints[i].timestamp), x, padding.top + chartH + 8);
    }
    // Always label the last point
    if (dataPoints.length > 1) {
      const lastX = padding.left + chartW;
      ctx.fillText(formatTime(dataPoints[dataPoints.length - 1].timestamp), lastX, padding.top + chartH + 8);
    }

    // Plot the line
    ctx.strokeStyle = colors.line;
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.setLineDash([]);

    ctx.beginPath();
    for (let i = 0; i < dataPoints.length; i++) {
      const x = padding.left + (i / Math.max(dataPoints.length - 1, 1)) * chartW;
      const y = padding.top + chartH - ((dataPoints[i].usedPercent - yMin) / (yMax - yMin)) * chartH;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    // Area fill under the line
    const gradient = ctx.createLinearGradient(0, padding.top, 0, padding.top + chartH);
    gradient.addColorStop(0, colors.fillStart);
    gradient.addColorStop(1, colors.fillEnd);
    ctx.fillStyle = gradient;

    ctx.beginPath();
    for (let i = 0; i < dataPoints.length; i++) {
      const x = padding.left + (i / Math.max(dataPoints.length - 1, 1)) * chartW;
      const y = padding.top + chartH - ((dataPoints[i].usedPercent - yMin) / (yMax - yMin)) * chartH;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    // Close the path along the bottom
    const lastX = padding.left + ((dataPoints.length - 1) / Math.max(dataPoints.length - 1, 1)) * chartW;
    ctx.lineTo(lastX, padding.top + chartH);
    ctx.lineTo(padding.left, padding.top + chartH);
    ctx.closePath();
    ctx.fill();

    // Draw dots at each data point
    ctx.fillStyle = colors.line;
    for (let i = 0; i < dataPoints.length; i++) {
      const x = padding.left + (i / Math.max(dataPoints.length - 1, 1)) * chartW;
      const y = padding.top + chartH - ((dataPoints[i].usedPercent - yMin) / (yMax - yMin)) * chartH;
      ctx.beginPath();
      ctx.arc(x, y, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function scheduleRedraw() {
    if (animationId) {
      cancelAnimationFrame(animationId);
    }
    animationId = requestAnimationFrame(() => {
      draw();
      animationId = null;
    });
  }

  function addSnapshot(snapshot) {
    dataPoints.push(snapshot);
    if (dataPoints.length > MAX_POINTS) {
      dataPoints = dataPoints.slice(-MAX_POINTS);
    }
    updateStats(snapshot);
    vscode.setState({ dataPoints: dataPoints });
    scheduleRedraw();
  }

  window.addEventListener('message', function (event) {
    const message = event.data;
    switch (message.type) {
      case 'update':
        addSnapshot(message.snapshot);
        break;
      case 'restore':
        if (Array.isArray(message.dataPoints) && message.dataPoints.length > 0) {
          dataPoints = message.dataPoints.slice(-MAX_POINTS);
          updateStats(dataPoints[dataPoints.length - 1]);
          vscode.setState({ dataPoints: dataPoints });
          scheduleRedraw();
        }
        break;
    }
  });

  // Restore persisted state from VS Code's webview state API
  const previousState = vscode.getState();
  if (previousState && Array.isArray(previousState.dataPoints) && previousState.dataPoints.length > 0) {
    dataPoints = previousState.dataPoints.slice(-MAX_POINTS);
    updateStats(dataPoints[dataPoints.length - 1]);
    scheduleRedraw();
  }

  window.addEventListener('resize', function () {
    resizeCanvas();
  });

  resizeCanvas();

  vscode.postMessage({ type: 'ready' });
}());
