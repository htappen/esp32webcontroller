import './styles.css';
import { GamepadController } from './gamepad_controller.js';
import { PageStateController } from './page_state_controller.js';

const runtimeConfig = window.__CONTROLLER_CONFIG || {};

let pageController;

pageController = new PageStateController({
  apiBase: runtimeConfig.apiBase || '',
  networkStatusEl: document.getElementById('network-status'),
  hostStatusEl: document.getElementById('host-status'),
  transportStatusEl: document.getElementById('transport-status'),
  layoutStatusEl: document.getElementById('layout-status'),
  hostActionStatusEl: document.getElementById('host-action-status'),
  deviceNameEl: document.getElementById('device-name'),
  deviceHostnameEl: document.getElementById('device-hostname'),
  controllerSlotBadgeEl: document.getElementById('controller-slot-badge'),
  controllerSlotLabelEl: document.getElementById('controller-slot-label'),
  staForm: document.getElementById('sta-form'),
  forgetHostEl: document.getElementById('forget-host'),
  layoutSelectEl: document.getElementById('layout-select'),
  configOpenEl: document.getElementById('config-open'),
  configCloseEl: document.getElementById('config-close'),
  configBackdropEl: document.getElementById('config-backdrop'),
  configModalEl: document.getElementById('config-modal'),
  gamepadController: new GamepadController({
    stageEl: document.getElementById('controller-stage'),
    leftEl: document.getElementById('gpad-display-left'),
    rightEl: document.getElementById('gpad-display-right'),
    wsUrl: runtimeConfig.wsUrl || `ws://${location.hostname}:81`,
    onTransportStatus: (message) => pageController.setTransportStatus(message),
    onSessionStatus: (session) => pageController.setControllerSession(session),
  }),
});

window.__controllerApp = {
  pageController,
  gamepadController: pageController.gamepadController,
};

pageController.start();
