export function initController(root, ws) {
  if (!root) {
    return;
  }

  root.innerHTML = '<h1>ESP32 Controller</h1><p>TODO: wire virtual-gamepad-lib in dev workspace.</p>';

  let seq = 0;
  function sendNeutral() {
    ws.send({
      t: Date.now(),
      seq: ++seq,
      btn: { a: 0, b: 0, x: 0, y: 0, lb: 0, rb: 0, back: 0, start: 0, ls: 0, rs: 0, du: 0, dd: 0, dl: 0, dr: 0 },
      ax: { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 },
    });
    requestAnimationFrame(sendNeutral);
  }

  sendNeutral();
}
