export class PageStateController {
  constructor(opts) {
    this.statusEl = opts.statusEl;
    this.networkStatusEl = opts.networkStatusEl;
    this.hostStatusEl = opts.hostStatusEl;
    this.staForm = opts.staForm;
    this.pairingToggleEl = opts.pairingToggleEl;
    this.gamepadController = opts.gamepadController;
    this.pairingEnabled = true;
  }

  async start() {
    this.staForm.addEventListener('submit', (event) => this.onStaSubmit(event));
    this.pairingToggleEl.addEventListener('click', () => this.onPairingToggle());

    await this.gamepadController.start();
    await this.refreshStatus();
    setInterval(() => this.refreshStatus(), 5000);
  }

  setTransportStatus(message) {
    this.statusEl.textContent = message;
  }

  async postJson(url, payload) {
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

  renderStatus(status) {
    if (!status) {
      this.networkStatusEl.textContent = 'Network status unavailable';
      this.hostStatusEl.textContent = 'Host status unavailable';
      return;
    }

    const net = status.network || {};
    const host = status.host || {};
    const controller = status.controller || {};

    this.networkStatusEl.textContent =
      `Mode: ${net.mode || 'unknown'} | AP: ${net.apActive ? 'up' : 'down'} | STA: ${net.staConnected ? 'connected' : 'disconnected'} | AP IP: ${net.apIp || '-'} | STA IP: ${net.staIp || '-'}`;
    this.hostStatusEl.textContent =
      `Connected: ${host.connected ? 'yes' : 'no'} | Advertising: ${host.advertising ? 'yes' : 'no'} | WS: ${controller.wsConnected ? 'yes' : 'no'}`;

    this.pairingEnabled = !!host.advertising;
    this.pairingToggleEl.textContent = this.pairingEnabled ? 'Disable Pairing' : 'Enable Pairing';
  }

  async refreshStatus() {
    try {
      const res = await fetch('/api/status');
      if (!res.ok) {
        throw new Error(`status ${res.status}`);
      }

      const data = await res.json();
      this.renderStatus(data);
    } catch (err) {
      this.networkStatusEl.textContent = `Network status error: ${err.message}`;
      this.hostStatusEl.textContent = `Host status error: ${err.message}`;
    }
  }

  async onStaSubmit(event) {
    event.preventDefault();

    const formData = new FormData(this.staForm);
    const ssid = String(formData.get('ssid') || '').trim();
    const pass = String(formData.get('pass') || '');

    if (!ssid) {
      this.networkStatusEl.textContent = 'SSID is required';
      return;
    }

    try {
      await this.postJson('/api/network/sta', { ssid, pass });
      this.networkStatusEl.textContent = 'Connecting to shared Wi-Fi...';
      setTimeout(() => this.refreshStatus(), 1500);
    } catch (err) {
      this.networkStatusEl.textContent = `Failed to set STA credentials: ${err.message}`;
    }
  }

  async onPairingToggle() {
    try {
      await this.postJson('/api/host/pairing', { enabled: !this.pairingEnabled });
      setTimeout(() => this.refreshStatus(), 250);
    } catch (err) {
      this.hostStatusEl.textContent = `Failed to update pairing: ${err.message}`;
    }
  }
}
