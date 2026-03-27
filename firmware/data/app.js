import { GamepadController } from '/gamepad_controller.js';
import { PageStateController } from '/page_state_controller.js';

let pageController;

pageController = new PageStateController({
  statusEl: document.getElementById('status'),
  networkStatusEl: document.getElementById('network-status'),
  hostStatusEl: document.getElementById('host-status'),
  layoutStatusEl: document.getElementById('layout-status'),
  staForm: document.getElementById('sta-form'),
  layoutSelectEl: document.getElementById('layout-select'),
  pairingToggleEl: document.getElementById('pairing-toggle'),
  configOpenEl: document.getElementById('config-open'),
  configCloseEl: document.getElementById('config-close'),
  configBackdropEl: document.getElementById('config-backdrop'),
  configModalEl: document.getElementById('config-modal'),
  gamepadController: new GamepadController({
    rootEl: document.getElementById('controller-root'),
    wsUrl: `ws://${location.hostname}:81`,
    onTransportStatus: (message) => pageController.setTransportStatus(message),
  }),
});

window.__controllerApp = {
  pageController,
  gamepadController: pageController.gamepadController,
};

pageController.start();
