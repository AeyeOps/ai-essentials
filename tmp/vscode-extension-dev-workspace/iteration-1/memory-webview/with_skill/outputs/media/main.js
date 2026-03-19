(function () {
  'use strict';

  const vscode = acquireVsCodeApi();

  let maxDataPoints = 60;
  let snapshots = [];
  let isPaused = false;

  const previousState = vscode.getState();
  if (previousState) {
    snapshots = previousState.snapshots || [];
    isPaused = previousState.isPaused || false;
    if (isPaused) {
      updatePauseButton(true);
    }
  }

  const canvas = document.getElementById('chart');
  const ctx = canvas.getContext('2d');

  const usedValueEl = document.getElementById('usedValue');
  const freeValueEl = document.getElementById('freeValue');
  const totalValueEl = document.getElementById('totalValue');
  const percentValueEl = document.getElementById('percentValue');

  const pauseBtn = document.getElementById('pauseBtn');
  const clearBtn = document.getElementById('clearBtn');

  pauseBtn.addEventListener('click', function () {
    isPaused = !isPaused;
    updatePauseButton(isPaused);
    vscode.postMessage({ type: isPaused ? 'pause' : 'resume' });
    saveState();
  });

  clearBtn.addEventListener('click', function () {
    snapshots = [];
    saveState();
    drawChart();
    vscode.postMessage({ type: 'clear' });
  });

  function updatePauseButton(paused) {
    pauseBtn.textContent = paused ? 'Resume' : 'Pause';
    if (paused) {
      pauseBtn.classList.add('active');
    } else {
      pauseBtn.classList.remove('active');
    }
  }

  window.addEventListener('message', function (event) {
    var message = event.data;

    switch (message.type) {
      case 'snapshot':
        handleSnapshot(message.data);
        break;
      case 'restore':
        if (message.data && message.data.snapshots) {
          snapshots = message.data.snapshots;
          isPaused = message.data.isPaused || false;
          updatePauseButton(isPaused);
          drawChart();
          updateStats();
        }
        break;
      case 'configUpdate':
        if (typeof message.maxDataPoints === 'number') {
          maxDataPoints = message.maxDataPoints;
          while (snapshots.length > maxDataPoints) {
            snapshots.shift();
          }
          saveState();
          drawChart();
        }
        break;
    }
  });

  function handleSnapshot(data) {
    snapshots.push(data);
    while (snapshots.length > maxDataPoints) {
      snapshots.shift();
    }
    saveState();
    updateStats();
    drawChart();
  }

  function updateStats() {
    if (snapshots.length === 0) {
      return;
    }
    var latest = snapshots[snapshots.length - 1];
    usedValueEl.textContent = formatMB(latest.usedMB);
    freeValueEl.textContent = formatMB(latest.freeMB);
    totalValueEl.textContent = formatMB(latest.totalMB);
    percentValueEl.textContent = latest.usedPercent + '%';
  }

  function formatMB(mb) {
    if (mb >= 1024) {
      return (mb / 1024).toFixed(1) + ' GB';
    }
    return mb + ' MB';
  }

  function saveState() {
    vscode.setState({ snapshots: snapshots, isPaused: isPaused });
  }

  function getColors() {
    var style = getComputedStyle(document.body);
    var isDark = document.body.classList.contains('vscode-dark') ||
                 document.body.classList.contains('vscode-high-contrast');

    return {
      usedFill: isDark ? 'rgba(79, 195, 247, 0.3)' : 'rgba(2, 136, 209, 0.2)',
      usedStroke: isDark ? '#4fc3f7' : '#0288d1',
      freeFill: isDark ? 'rgba(129, 199, 132, 0.15)' : 'rgba(56, 142, 60, 0.1)',
      freeStroke: isDark ? '#81c784' : '#388e3c',
      gridLine: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)',
      axisText: style.getPropertyValue('--vscode-descriptionForeground').trim() || (isDark ? '#888' : '#666'),
      zeroLine: isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)'
    };
  }

  function drawChart() {
    var dpr = window.devicePixelRatio || 1;
    var rect = canvas.parentElement.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    canvas.style.width = rect.width + 'px';
    canvas.style.height = rect.height + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    var w = rect.width;
    var h = rect.height;

    ctx.clearRect(0, 0, w, h);

    if (snapshots.length < 2) {
      ctx.fillStyle = getColors().axisText;
      ctx.font = '12px ' + getComputedStyle(document.body).fontFamily;
      ctx.textAlign = 'center';
      ctx.fillText('Waiting for data...', w / 2, h / 2);
      return;
    }

    var colors = getColors();
    var padding = { top: 20, right: 20, bottom: 40, left: 60 };
    var chartW = w - padding.left - padding.right;
    var chartH = h - padding.top - padding.bottom;

    var maxTotal = 0;
    for (var i = 0; i < snapshots.length; i++) {
      if (snapshots[i].totalMB > maxTotal) {
        maxTotal = snapshots[i].totalMB;
      }
    }
    var yMax = Math.ceil(maxTotal / 1024) * 1024;
    if (yMax === 0) {
      yMax = 1024;
    }

    var gridLines = 5;
    ctx.strokeStyle = colors.gridLine;
    ctx.lineWidth = 1;
    ctx.font = '11px ' + getComputedStyle(document.body).fontFamily;
    ctx.fillStyle = colors.axisText;
    ctx.textAlign = 'right';

    for (var g = 0; g <= gridLines; g++) {
      var yVal = (yMax / gridLines) * g;
      var yPos = padding.top + chartH - (g / gridLines) * chartH;

      ctx.beginPath();
      ctx.moveTo(padding.left, yPos);
      ctx.lineTo(w - padding.right, yPos);
      ctx.stroke();

      var label = yVal >= 1024 ? (yVal / 1024).toFixed(0) + ' GB' : yVal.toFixed(0) + ' MB';
      ctx.fillText(label, padding.left - 8, yPos + 4);
    }

    var timeSpan = snapshots[snapshots.length - 1].timestamp - snapshots[0].timestamp;
    ctx.textAlign = 'center';
    var timeLabels = Math.min(6, snapshots.length);
    for (var t = 0; t < timeLabels; t++) {
      var idx = Math.floor((t / (timeLabels - 1)) * (snapshots.length - 1));
      var xPos = padding.left + (idx / (snapshots.length - 1)) * chartW;
      var date = new Date(snapshots[idx].timestamp);
      var timeStr = date.getHours().toString().padStart(2, '0') + ':' +
                    date.getMinutes().toString().padStart(2, '0') + ':' +
                    date.getSeconds().toString().padStart(2, '0');
      ctx.fillText(timeStr, xPos, h - padding.bottom + 20);
    }

    function xForIndex(idx) {
      return padding.left + (idx / (snapshots.length - 1)) * chartW;
    }

    function yForValue(val) {
      return padding.top + chartH - (val / yMax) * chartH;
    }

    ctx.beginPath();
    ctx.moveTo(xForIndex(0), yForValue(snapshots[0].totalMB));
    for (var i = 1; i < snapshots.length; i++) {
      ctx.lineTo(xForIndex(i), yForValue(snapshots[i].totalMB));
    }
    for (var i = snapshots.length - 1; i >= 0; i--) {
      ctx.lineTo(xForIndex(i), yForValue(snapshots[i].usedMB));
    }
    ctx.closePath();
    ctx.fillStyle = colors.freeFill;
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(xForIndex(0), yForValue(snapshots[0].usedMB));
    for (var i = 1; i < snapshots.length; i++) {
      ctx.lineTo(xForIndex(i), yForValue(snapshots[i].usedMB));
    }
    for (var i = snapshots.length - 1; i >= 0; i--) {
      ctx.lineTo(xForIndex(i), yForValue(0));
    }
    ctx.closePath();
    ctx.fillStyle = colors.usedFill;
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(xForIndex(0), yForValue(snapshots[0].usedMB));
    for (var i = 1; i < snapshots.length; i++) {
      ctx.lineTo(xForIndex(i), yForValue(snapshots[i].usedMB));
    }
    ctx.strokeStyle = colors.usedStroke;
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(xForIndex(0), yForValue(snapshots[0].totalMB));
    for (var i = 1; i < snapshots.length; i++) {
      ctx.lineTo(xForIndex(i), yForValue(snapshots[i].totalMB));
    }
    ctx.strokeStyle = colors.freeStroke;
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 4]);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  var resizeTimer;
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(drawChart, 100);
  });

  if (snapshots.length > 0) {
    updateStats();
    drawChart();
  }

  vscode.postMessage({ type: 'ready' });
})();
