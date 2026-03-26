import { GamepadController } from '/gamepad_controller.js';
import { PageStateController } from '/page_state_controller.js';

let pageController;

pageController = new PageStateController({
  statusEl: document.getElementById('status'),
  networkStatusEl: document.getElementById('network-status'),
  hostStatusEl: document.getElementById('host-status'),
  staForm: document.getElementById('sta-form'),
  pairingToggleEl: document.getElementById('pairing-toggle'),
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
