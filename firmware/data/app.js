(() => {
  const statusEl = document.getElementById('status');
  const networkStatusEl = document.getElementById('network-status');
  const hostStatusEl = document.getElementById('host-status');
  const staForm = document.getElementById('sta-form');
  const pairingToggleEl = document.getElementById('pairing-toggle');
  const wsUrl = `ws://${location.hostname}:81`;
  let ws;
  let seq = 0;
  let pairingEnabled = true;

  // Placeholder controller state until virtual-gamepad-lib wiring is completed.
  const state = {
    t: 0,
    seq: 0,
    btn: { a: 0, b: 0, x: 0, y: 0, lb: 0, rb: 0, back: 0, start: 0, ls: 0, rs: 0, du: 0, dd: 0, dl: 0, dr: 0 },
    ax: { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 },
  };

  function connect() {
    ws = new WebSocket(wsUrl);
    ws.onopen = () => {
      statusEl.textContent = 'Connected';
    };
    ws.onclose = () => {
      statusEl.textContent = 'Disconnected, retrying...';
      setTimeout(connect, 1000);
    };
    ws.onerror = () => {
      statusEl.textContent = 'WebSocket error';
    };
  }

  function tick() {
    if (ws && ws.readyState === WebSocket.OPEN) {
      state.t = Date.now();
      state.seq = ++seq;
      ws.send(JSON.stringify(state));
    }
    requestAnimationFrame(tick);
  }

  function initVirtualGamepad() {
    const root = document.getElementById('controller-root');
    root.textContent = 'TODO: initialize virtual-gamepad-lib here.';
  }

  async function postJson(url, payload) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      throw new Error(`Request failed: ${res.status}`);
    }
    return res.json().catch(() => ({}));
  }

  function renderStatus(status) {
    if (!status) {
      networkStatusEl.textContent = 'Network status unavailable';
      hostStatusEl.textContent = 'Host status unavailable';
      return;
    }

    const net = status.network || {};
    const host = status.host || {};
    networkStatusEl.textContent =
      `Mode: ${net.mode || 'unknown'} | AP: ${net.apActive ? 'up' : 'down'} | STA: ${net.staConnected ? 'connected' : 'disconnected'} | AP IP: ${net.apIp || '-'} | STA IP: ${net.staIp || '-'}`;
    hostStatusEl.textContent =
      `Connected: ${host.connected ? 'yes' : 'no'} | Advertising: ${host.advertising ? 'yes' : 'no'}`;
    pairingEnabled = !!host.advertising;
    pairingToggleEl.textContent = pairingEnabled ? 'Disable Pairing' : 'Enable Pairing';
  }

  async function refreshStatus() {
    try {
      const res = await fetch('/api/status');
      if (!res.ok) {
        throw new Error(`status ${res.status}`);
      }
      const data = await res.json();
      renderStatus(data);
    } catch (err) {
      networkStatusEl.textContent = `Network status error: ${err.message}`;
      hostStatusEl.textContent = `Host status error: ${err.message}`;
    }
  }

  async function onStaSubmit(event) {
    event.preventDefault();
    const formData = new FormData(staForm);
    const ssid = String(formData.get('ssid') || '').trim();
    const pass = String(formData.get('pass') || '');
    if (!ssid) {
      networkStatusEl.textContent = 'SSID is required';
      return;
    }
    try {
      await postJson('/api/network/sta', { ssid, pass });
      networkStatusEl.textContent = 'Connecting to shared Wi-Fi...';
      setTimeout(refreshStatus, 1500);
    } catch (err) {
      networkStatusEl.textContent = `Failed to set STA credentials: ${err.message}`;
    }
  }

  async function onPairingToggle() {
    try {
      await postJson('/api/host/pairing', { enabled: !pairingEnabled });
      setTimeout(refreshStatus, 250);
    } catch (err) {
      hostStatusEl.textContent = `Failed to update pairing: ${err.message}`;
    }
  }

  initVirtualGamepad();
  staForm.addEventListener('submit', onStaSubmit);
  pairingToggleEl.addEventListener('click', onPairingToggle);
  connect();
  refreshStatus();
  setInterval(refreshStatus, 5000);
  tick();
})();
