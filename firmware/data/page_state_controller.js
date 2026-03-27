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
    detailParts.push(`trying ${net.candidateStaSsid || net.savedStaSsid || 'saved Wi-Fi'}`);
  } else if (net.staConnected) {
    detailParts.push(`connected to ${net.activeStaSsid || net.savedStaSsid || 'shared Wi-Fi'}`);
  } else if (net.apFallbackActive) {
    detailParts.push('ESP32 fallback AP available');
  } else if (!net.hasSavedStaConfig) {
    detailParts.push('no saved shared Wi-Fi yet');
  }

  if (net.apActive && net.apIp) {
    detailParts.push(`AP ${net.apIp}`);
  }
  if (net.staConnected && net.staIp) {
    detailParts.push(`STA ${net.staIp}`);
  }
  if (net.lastCandidateFailed) {
    detailParts.push('last Wi-Fi update failed, previous saved network kept');
  }

  return `${state.replaceAll('_', ' ')}${detailParts.length ? ' | ' : ''}${detailParts.join(' | ')}`;
}

export class PageStateController {
  constructor(opts) {
    this.statusEl = opts.statusEl;
    this.networkStatusEl = opts.networkStatusEl;
    this.hostStatusEl = opts.hostStatusEl;
    this.layoutStatusEl = opts.layoutStatusEl;
    this.staForm = opts.staForm;
    this.layoutSelectEl = opts.layoutSelectEl;
    this.pairingToggleEl = opts.pairingToggleEl;
    this.configOpenEl = opts.configOpenEl;
    this.configCloseEl = opts.configCloseEl;
    this.configBackdropEl = opts.configBackdropEl;
    this.configModalEl = opts.configModalEl;
    this.gamepadController = opts.gamepadController;
    this.pairingEnabled = true;
  }

  async start() {
    this.staForm.addEventListener('submit', (event) => this.onStaSubmit(event));
    this.layoutSelectEl.addEventListener('change', (event) => this.onLayoutChange(event));
    this.pairingToggleEl.addEventListener('click', () => this.onPairingToggle());
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
    setInterval(() => this.refreshStatus(), 2500);
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

    this.networkStatusEl.textContent = formatNetworkStatus(net);
    this.hostStatusEl.textContent =
      `Host ${host.connected ? 'connected' : 'ready'} | BLE advertising ${host.advertising ? 'on' : 'off'} | browser link ${controller.wsConnected ? 'live' : 'idle'}`;

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
      this.networkStatusEl.textContent = `Trying ${ssid}. The ESP32 will only save it after a successful connection.`;
      setTimeout(() => this.refreshStatus(), 1500);
    } catch (err) {
      this.networkStatusEl.textContent = `Failed to start shared Wi-Fi update: ${err.message}`;
    }
  }

  onLayoutChange(event) {
    const nextValue = String(event.target.value || DEFAULT_LAYOUT);
    setCookie(CONTROLLER_LAYOUT_COOKIE, nextValue, CONTROLLER_LAYOUT_COOKIE_MAX_AGE);
    this.layoutStatusEl.textContent = `Layout saved for this browser: ${event.target.selectedOptions[0].textContent}`;
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
