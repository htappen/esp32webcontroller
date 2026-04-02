import { setupPresetInteractiveGamepad } from '../../third_party/virtual-gamepad-lib/dist/helpers.js';
import { GamepadEmulator } from '../../third_party/virtual-gamepad-lib/dist/GamepadEmulator.js';
import { gamepadEmulationState } from '../../third_party/virtual-gamepad-lib/dist/enums.js';
import LEFT_GPAD_SVG_SOURCE_CODE from '../../third_party/virtual-gamepad-lib/gamepad_assets/rounded/display-gamepad-left.svg?raw';
import RIGHT_GPAD_SVG_SOURCE_CODE from '../../third_party/virtual-gamepad-lib/gamepad_assets/rounded/display-gamepad-right.svg?raw';
import {
  AXIS_INDEX_TO_KEY,
  BUTTON_INDEX_TO_KEY,
  FULL_STATE_INTERVAL_MS,
  TRIGGER_BUTTON_INDEX_TO_AXIS_KEY,
  createNeutralControllerState,
} from './schema.js';

export class GamepadController {
  constructor(opts) {
    this.stageEl = opts.stageEl;
    this.leftEl = opts.leftEl;
    this.rightEl = opts.rightEl;
    this.wsUrl = opts.wsUrl;
    this.onTransportStatus = opts.onTransportStatus;

    this.emulatedGamepadIndex = 0;
    this.activeEmulatedGamepadIndex = null;
    this.gpadEmulator = new GamepadEmulator(0.1);
    this.gpadApiWrapper = null;
    this.ws = null;
    this.seq = 0;
    this.retryDelayMs = 1000;
    this.fullStateIntervalId = null;
    this.state = createNeutralControllerState();
  }

  async start() {
    this.initVirtualGamepad();
    this.bindGamepadEvents();
    this.connectWs();
    this.startFullStateLoop();
  }

  setTransportStatus(message) {
    if (typeof this.onTransportStatus === 'function') {
      this.onTransportStatus(message);
    }
  }

  initVirtualGamepad() {
    this.leftEl.innerHTML = LEFT_GPAD_SVG_SOURCE_CODE;
    this.rightEl.innerHTML = RIGHT_GPAD_SVG_SOURCE_CODE;

    const { gpadApiWrapper } = setupPresetInteractiveGamepad(this.stageEl, {
      AllowDpadDiagonals: true,
      GpadEmulator: this.gpadEmulator,
      EmulatedGamepadIndex: this.emulatedGamepadIndex,
      EmulatedGamepadOverlayMode: false,
    });
    this.gpadApiWrapper = gpadApiWrapper;
    this.refreshActiveEmulatedGamepadIndex();
  }

  connectWs() {
    this.setTransportStatus('Opening browser link...');
    this.ws = new WebSocket(this.wsUrl);

    this.ws.onopen = () => {
      this.retryDelayMs = 1000;
      this.setTransportStatus('Browser link live.');
      this.sendFullState();
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

  bindGamepadEvents() {
    if (!this.gpadApiWrapper) {
      return;
    }

    this.gpadApiWrapper.onGamepadConnect(() => {
      this.refreshActiveEmulatedGamepadIndex();
    });

    this.gpadApiWrapper.onGamepadDisconnect(() => {
      this.refreshActiveEmulatedGamepadIndex();
    });

    this.gpadApiWrapper.onGamepadButtonChange((gpadIndex, gpad, buttonChanges) => {
      if (!this.isActiveEmulatedGamepad(gpadIndex, gpad)) {
        return;
      }

      const btnDelta = {};
      const axDelta = {};
      for (let index = 0; index < buttonChanges.length; index += 1) {
        if (!buttonChanges[index]) {
          continue;
        }

        const button = gpad?.buttons?.[index];
        if (!button) {
          continue;
        }

        const buttonKey = BUTTON_INDEX_TO_KEY[index];
        if (buttonKey) {
          const nextValue = button.pressed ? 1 : 0;
          if (this.state.btn[buttonKey] !== nextValue) {
            this.state.btn[buttonKey] = nextValue;
            btnDelta[buttonKey] = nextValue;
          }
        }

        const triggerAxisKey = TRIGGER_BUTTON_INDEX_TO_AXIS_KEY[index];
        if (triggerAxisKey) {
          const nextValue = this.clamp(button.value, 0, 1);
          if (this.state.ax[triggerAxisKey] !== nextValue) {
            this.state.ax[triggerAxisKey] = nextValue;
            axDelta[triggerAxisKey] = nextValue;
          }
        }
      }

      this.sendDeltaState(btnDelta, axDelta);
    });

    this.gpadApiWrapper.onGamepadAxisChange((gpadIndex, gpad, axisChangesMask) => {
      if (!this.isActiveEmulatedGamepad(gpadIndex, gpad)) {
        return;
      }

      const axDelta = {};
      for (let index = 0; index < axisChangesMask.length; index += 1) {
        if (!axisChangesMask[index]) {
          continue;
        }

        const axisKey = AXIS_INDEX_TO_KEY[index];
        if (!axisKey) {
          continue;
        }

        const nextValue = this.readAxis(gpad, index);
        if (this.state.ax[axisKey] !== nextValue) {
          this.state.ax[axisKey] = nextValue;
          axDelta[axisKey] = nextValue;
        }
      }

      this.sendDeltaState({}, axDelta);
    });
  }

  refreshActiveEmulatedGamepadIndex() {
    const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
    const emulatedGamepad = Array.from(gamepads).find(
      (gpad) => gpad && gpad.emulation === gamepadEmulationState.emulated,
    );
    this.activeEmulatedGamepadIndex = emulatedGamepad ? emulatedGamepad.index : null;
  }

  isActiveEmulatedGamepad(gpadIndex, gpad) {
    if (!gpad || gpad.emulation !== gamepadEmulationState.emulated) {
      return false;
    }

    if (this.activeEmulatedGamepadIndex !== gpadIndex) {
      this.refreshActiveEmulatedGamepadIndex();
    }

    return this.activeEmulatedGamepadIndex === gpadIndex;
  }

  startFullStateLoop() {
    if (this.fullStateIntervalId !== null) {
      window.clearInterval(this.fullStateIntervalId);
    }

    this.fullStateIntervalId = window.setInterval(() => {
      this.sendFullState();
    }, FULL_STATE_INTERVAL_MS);
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

  sendPacket(packet) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }

    packet.t = Date.now();
    packet.seq = ++this.seq;
    this.ws.send(JSON.stringify(packet));
  }

  sendDeltaState(btnDelta = {}, axDelta = {}) {
    if (Object.keys(btnDelta).length === 0 && Object.keys(axDelta).length === 0) {
      return;
    }

    const packet = {};
    if (Object.keys(btnDelta).length > 0) {
      packet.btn = btnDelta;
    }
    if (Object.keys(axDelta).length > 0) {
      packet.ax = axDelta;
    }
    this.sendPacket(packet);
  }

  sendFullState() {
    this.sendPacket({
      btn: { ...this.state.btn },
      ax: { ...this.state.ax },
    });
  }
}
