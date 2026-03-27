import { setupPresetInteractiveGamepad } from '../../third_party/virtual-gamepad-lib/dist/helpers.js';
import { GamepadEmulator } from '../../third_party/virtual-gamepad-lib/dist/GamepadEmulator.js';
import LEFT_GPAD_SVG_SOURCE_CODE from '../../third_party/virtual-gamepad-lib/gamepad_assets/rounded/display-gamepad-left.svg?raw';
import RIGHT_GPAD_SVG_SOURCE_CODE from '../../third_party/virtual-gamepad-lib/gamepad_assets/rounded/display-gamepad-right.svg?raw';

export class GamepadController {
  constructor(opts) {
    this.stageEl = opts.stageEl;
    this.leftEl = opts.leftEl;
    this.rightEl = opts.rightEl;
    this.wsUrl = opts.wsUrl;
    this.onTransportStatus = opts.onTransportStatus;

    this.emulatedGamepadIndex = 0;
    this.gpadEmulator = new GamepadEmulator(0.1);
    this.ws = null;
    this.seq = 0;
    this.retryDelayMs = 1000;
    this.state = {
      t: 0,
      seq: 0,
      btn: { a: 0, b: 0, x: 0, y: 0, lb: 0, rb: 0, back: 0, start: 0, ls: 0, rs: 0, du: 0, dd: 0, dl: 0, dr: 0 },
      ax: { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 },
    };
  }

  async start() {
    this.initVirtualGamepad();
    this.connectWs();
    this.tick();
  }

  setTransportStatus(message) {
    if (typeof this.onTransportStatus === 'function') {
      this.onTransportStatus(message);
    }
  }

  initVirtualGamepad() {
    this.leftEl.innerHTML = LEFT_GPAD_SVG_SOURCE_CODE;
    this.rightEl.innerHTML = RIGHT_GPAD_SVG_SOURCE_CODE;

    setupPresetInteractiveGamepad(this.stageEl, {
      AllowDpadDiagonals: true,
      GpadEmulator: this.gpadEmulator,
      EmulatedGamepadIndex: this.emulatedGamepadIndex,
      EmulatedGamepadOverlayMode: true,
    });
  }

  connectWs() {
    this.setTransportStatus('Opening browser link...');
    this.ws = new WebSocket(this.wsUrl);

    this.ws.onopen = () => {
      this.retryDelayMs = 1000;
      this.setTransportStatus('Browser link live.');
    };

    this.ws.onclose = () => {
      this.setTransportStatus('Browser link lost. Retrying...');
      window.setTimeout(() => this.connectWs(), this.retryDelayMs);
      this.retryDelayMs = Math.min(this.retryDelayMs * 2, 5000);
    };

    this.ws.onerror = () => {
      this.setTransportStatus('Browser link error.');
    };
  }

  clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  readButton(gpad, index) {
    if (!gpad?.buttons?.[index]) {
      return { pressed: false, value: 0 };
    }

    const button = gpad.buttons[index];
    return {
      pressed: Boolean(button.pressed),
      value: typeof button.value === 'number' ? button.value : 0,
    };
  }

  readAxis(gpad, index) {
    const value = gpad?.axes?.[index];
    if (typeof value !== 'number') {
      return 0;
    }

    return this.clamp(value, -1, 1);
  }

  syncStateFromGamepad() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const gpad = pads?.[this.emulatedGamepadIndex] ?? null;

    const b0 = this.readButton(gpad, 0);
    const b1 = this.readButton(gpad, 1);
    const b2 = this.readButton(gpad, 2);
    const b3 = this.readButton(gpad, 3);
    const b4 = this.readButton(gpad, 4);
    const b5 = this.readButton(gpad, 5);
    const b6 = this.readButton(gpad, 6);
    const b7 = this.readButton(gpad, 7);
    const b8 = this.readButton(gpad, 8);
    const b9 = this.readButton(gpad, 9);
    const b10 = this.readButton(gpad, 10);
    const b11 = this.readButton(gpad, 11);
    const b12 = this.readButton(gpad, 12);
    const b13 = this.readButton(gpad, 13);
    const b14 = this.readButton(gpad, 14);
    const b15 = this.readButton(gpad, 15);

    this.state.btn.a = b0.pressed ? 1 : 0;
    this.state.btn.b = b1.pressed ? 1 : 0;
    this.state.btn.x = b2.pressed ? 1 : 0;
    this.state.btn.y = b3.pressed ? 1 : 0;
    this.state.btn.lb = b4.pressed ? 1 : 0;
    this.state.btn.rb = b5.pressed ? 1 : 0;
    this.state.btn.back = b8.pressed ? 1 : 0;
    this.state.btn.start = b9.pressed ? 1 : 0;
    this.state.btn.ls = b10.pressed ? 1 : 0;
    this.state.btn.rs = b11.pressed ? 1 : 0;
    this.state.btn.du = b12.pressed ? 1 : 0;
    this.state.btn.dd = b13.pressed ? 1 : 0;
    this.state.btn.dl = b14.pressed ? 1 : 0;
    this.state.btn.dr = b15.pressed ? 1 : 0;

    this.state.ax.lx = this.readAxis(gpad, 0);
    this.state.ax.ly = this.readAxis(gpad, 1);
    this.state.ax.rx = this.readAxis(gpad, 2);
    this.state.ax.ry = this.readAxis(gpad, 3);
    this.state.ax.lt = this.clamp(b6.value, 0, 1);
    this.state.ax.rt = this.clamp(b7.value, 0, 1);
  }

  sendCurrentState() {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    this.state.t = Date.now();
    this.state.seq = ++this.seq;
    this.ws.send(JSON.stringify(this.state));
  }

  tick() {
    this.syncStateFromGamepad();
    this.sendCurrentState();
    window.requestAnimationFrame(() => this.tick());
  }
}
