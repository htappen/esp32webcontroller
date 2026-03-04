import './styles.css';
import { initController } from './controller.js';
import { createWsClient } from './ws-client.js';

const ws = createWsClient(`ws://${location.hostname}:81`);
initController(document.getElementById('app'), ws);
