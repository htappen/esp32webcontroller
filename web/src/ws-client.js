export function createWsClient(url) {
  let ws = null;

  function connect() {
    ws = new WebSocket(url);
    ws.onclose = () => setTimeout(connect, 1000);
  }

  connect();

  return {
    send(payload) {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(payload));
      }
    },
  };
}
