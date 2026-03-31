const CONTROLLER_LAYOUT_COOKIE = 'controller_layout';
const CONTROLLER_LAYOUT_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;
const DEFAULT_LAYOUT = 'virtual-gamepad-default';

function setCookie(name, value, maxAgeSeconds) {
  document.cookie = `${name}=${encodeURIComponent(value)}; Max-Age=${maxAgeSeconds}; Path=/; SameSite=Lax`;
}

function getCookie(name) {
  const prefix = `${name}=`;
  const parts = document.cookie ? document.cookie.split('; ') : [];
  const entry = parts.find((item) => item.startsWith(prefix));
  return entry ? decodeURIComponent(entry.slice(prefix.length)) : '';
}

function formatNetworkStatus(net) {
  const state = net.connectionState || 'unknown';
  const detailParts = [];

  if (net.staConnecting) {
    detailParts.push(`Trying ${net.candidateStaSsid || net.savedStaSsid || 'saved Wi-Fi'}.`);
  } else if (net.staConnected) {
    detailParts.push(`Connected to ${net.activeStaSsid || net.savedStaSsid || 'shared Wi-Fi'}.`);
  } else if (net.apFallbackActive) {
    detailParts.push('Fallback AP available.');
  } else if (!net.hasSavedStaConfig) {
    detailParts.push('No saved shared Wi-Fi yet.');
  }

  if (net.apActive && net.apIp) {
    detailParts.push(`AP ${net.apIp}.`);
  }
  if (net.staConnected && net.staIp) {
    detailParts.push(`STA ${net.staIp}.`);
  }
  if (net.lastCandidateFailed) {
    detailParts.push('Last Wi-Fi update failed and the previous network was kept.');
  }

  const label = state.replaceAll('_', ' ');
  return `${label.charAt(0).toUpperCase()}${label.slice(1)}${detailParts.length ? '  ' : ''}${detailParts.join(' ')}`;
}

export class PageStateController {
  constructor(opts) {
    this.apiBase = opts.apiBase || '';
    this.networkStatusEl = opts.networkStatusEl;
    this.hostStatusEl = opts.hostStatusEl;
    this.transportStatusEl = opts.transportStatusEl;
    this.layoutStatusEl = opts.layoutStatusEl;
    this.hostActionStatusEl = opts.hostActionStatusEl;
    this.deviceNameEl = opts.deviceNameEl;
    this.deviceHostnameEl = opts.deviceHostnameEl;
    this.staForm = opts.staForm;
    this.forgetHostEl = opts.forgetHostEl;
    this.layoutSelectEl = opts.layoutSelectEl;
    this.configOpenEl = opts.configOpenEl;
    this.configCloseEl = opts.configCloseEl;
    this.configBackdropEl = opts.configBackdropEl;
    this.configModalEl = opts.configModalEl;
    this.gamepadController = opts.gamepadController;
  }

  async start() {
    this.staForm.addEventListener('submit', (event) => this.onStaSubmit(event));
    this.forgetHostEl.addEventListener('click', () => this.onForgetHost());
    this.layoutSelectEl.addEventListener('change', (event) => this.onLayoutChange(event));
    this.configOpenEl.addEventListener('click', () => this.openConfig());
    this.configCloseEl.addEventListener('click', () => this.closeConfig());
    this.configBackdropEl.addEventListener('click', () => this.closeConfig());
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        this.closeConfig();
      }
    });

    this.restoreLayoutPreference();
    await this.gamepadController.start();
    await this.refreshStatus();
    window.setInterval(() => this.refreshStatus(), 2500);
  }

  openConfig() {
    this.configModalEl.classList.remove('hidden');
    document.body.classList.add('modal-open');
  }

  closeConfig() {
    this.configModalEl.classList.add('hidden');
    document.body.classList.remove('modal-open');
  }

  restoreLayoutPreference() {
    const saved = getCookie(CONTROLLER_LAYOUT_COOKIE) || DEFAULT_LAYOUT;
    this.layoutSelectEl.value = saved;
    this.layoutStatusEl.textContent = `Layout saved for this browser: ${this.layoutSelectEl.selectedOptions[0].textContent}`;
  }

  setTransportStatus(message) {
    this.transportStatusEl.textContent = message;
  }

  async postJson(url, payload) {
    const res = await fetch(`${this.apiBase}${url}`, {
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
      this.networkStatusEl.textContent = 'Network status unavailable.';
      this.hostStatusEl.textContent = 'Host status unavailable.';
      return;
    }

    const net = status.network || {};
    const device = status.device || {};
    const host = status.host || {};
    const controller = status.controller || {};

    if (this.deviceNameEl) {
      this.deviceNameEl.textContent = device.friendlyName || 'ESP32 Pad';
    }
    if (this.deviceHostnameEl) {
      this.deviceHostnameEl.textContent = device.hostnameLocal
        ? `Open ${device.hostnameLocal}`
        : 'Device address unavailable.';
    }
    if (device.friendlyName) {
      document.title = `${device.friendlyName} Pad`;
    }

    this.networkStatusEl.textContent = formatNetworkStatus(net);
    this.hostStatusEl.textContent =
      `${host.bleName || 'BLE host'} ${host.connected ? 'connected' : 'ready'}  BLE advertising ${host.advertising ? 'on' : 'off'}  Browser ${controller.wsConnected ? 'live' : 'idle'}`;
  }

  async refreshStatus() {
    try {
      const res = await fetch(`${this.apiBase}/api/status`);
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
      this.networkStatusEl.textContent = 'SSID is required.';
      return;
    }

    try {
      await this.postJson('/api/network/sta', { ssid, pass });
      this.networkStatusEl.textContent = `Trying ${ssid}. The ESP32 will save it only after the connection succeeds.`;
      window.setTimeout(() => this.refreshStatus(), 1500);
    } catch (err) {
      this.networkStatusEl.textContent = `Failed to start shared Wi-Fi update: ${err.message}`;
    }
  }

  async onForgetHost() {
    this.forgetHostEl.disabled = true;
    this.hostActionStatusEl.textContent = 'Forgetting current Bluetooth host...';

    try {
      await this.postJson('/api/host/forget', {});
      this.hostActionStatusEl.textContent =
        'Current Bluetooth host forgotten. The ESP32 should resume advertising for a new host.';
      window.setTimeout(() => this.refreshStatus(), 500);
    } catch (err) {
      if (err.message === 'Request failed: 409') {
        this.hostActionStatusEl.textContent = 'No Bluetooth host is connected right now.';
      } else {
        this.hostActionStatusEl.textContent = `Failed to forget Bluetooth host: ${err.message}`;
      }
    } finally {
      this.forgetHostEl.disabled = false;
    }
  }

  onLayoutChange(event) {
    const nextValue = String(event.target.value || DEFAULT_LAYOUT);
    setCookie(CONTROLLER_LAYOUT_COOKIE, nextValue, CONTROLLER_LAYOUT_COOKIE_MAX_AGE);
    this.layoutStatusEl.textContent = `Layout saved for this browser: ${event.target.selectedOptions[0].textContent}`;
  }
}
