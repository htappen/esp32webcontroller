#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.request
import shutil
from urllib.parse import urlparse


def make_text_frame(payload: bytes) -> bytes:
    mask = os.urandom(4)
    first = bytes([0x81])
    length = len(payload)
    if length < 126:
        header = bytes([0x80 | length])
    elif length < 65536:
        header = bytes([0x80 | 126]) + length.to_bytes(2, "big")
    else:
        header = bytes([0x80 | 127]) + length.to_bytes(8, "big")
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return first + header + mask + masked


def read_exact(sock: socket.socket, count: int) -> bytes:
    payload = b""
    while len(payload) < count:
        chunk = sock.recv(count - len(payload))
        if not chunk:
            raise RuntimeError("websocket closed while reading frame")
        payload += chunk
    return payload


def read_frame(sock: socket.socket) -> tuple[int, bytes]:
    header = read_exact(sock, 2)
    first = header[0]
    second = header[1]
    opcode = first & 0x0F
    masked = (second & 0x80) != 0
    length = second & 0x7F
    if length == 126:
        length = int.from_bytes(read_exact(sock, 2), "big")
    elif length == 127:
        length = int.from_bytes(read_exact(sock, 8), "big")

    mask = read_exact(sock, 4) if masked else b""
    payload = read_exact(sock, length)
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return opcode, payload


def websocket_connect(ws_url: str) -> socket.socket:
    parsed = urlparse(ws_url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 80
    path = parsed.path or "/"
    if parsed.query:
        path += f"?{parsed.query}"

    raw = socket.create_connection((host, port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    ).encode("ascii")
    raw.sendall(request)

    response = b""
    while b"\r\n\r\n" not in response:
        chunk = raw.recv(4096)
        if not chunk:
            raise RuntimeError("websocket handshake closed unexpectedly")
        response += chunk

    header_blob = response.split(b"\r\n\r\n", 1)[0].decode("ascii", "replace")
    if " 101 " not in header_blob:
        raise RuntimeError(f"websocket upgrade failed: {header_blob}")

    accept = None
    for line in header_blob.split("\r\n")[1:]:
        if line.lower().startswith("sec-websocket-accept:"):
            accept = line.split(":", 1)[1].strip()
            break
    expected = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    ).decode("ascii")
    if accept != expected:
        raise RuntimeError("websocket accept header mismatch")

    return raw


class CdpClient:
    def __init__(self, ws_url: str):
        self.sock = websocket_connect(ws_url)
        self.next_id = 1

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, method: str, params: dict | None = None) -> int:
        message_id = self.next_id
        self.next_id += 1
        message = {"id": message_id, "method": method}
        if params:
            message["params"] = params
        self.sock.sendall(make_text_frame(json.dumps(message, separators=(",", ":")).encode("utf-8")))
        return message_id

    def recv(self) -> dict:
        opcode, payload = read_frame(self.sock)
        if opcode != 1:
            return {"opcode": opcode}
        return json.loads(payload.decode("utf-8"))

    def call(self, method: str, params: dict | None = None, timeout_seconds: float = 10.0) -> dict:
        message_id = self.send(method, params)
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            remaining = max(0.1, deadline - time.monotonic())
            self.sock.settimeout(remaining)
            message = self.recv()
            if message.get("id") == message_id:
                if "error" in message:
                    raise RuntimeError(f"CDP {method} failed: {message['error']}")
                return message.get("result", {})
        raise RuntimeError(f"timed out waiting for CDP response to {method}")

    def wait_for_event(self, method: str, timeout_seconds: float = 10.0) -> dict:
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            remaining = max(0.1, deadline - time.monotonic())
            self.sock.settimeout(remaining)
            message = self.recv()
            if message.get("method") == method:
                return message.get("params", {})
        raise RuntimeError(f"timed out waiting for CDP event {method}")

    def read_message(self, timeout_seconds: float = 0.1) -> dict | None:
        self.sock.settimeout(timeout_seconds)
        try:
            return self.recv()
        except socket.timeout:
            return None

    def evaluate(self, expression: str, timeout_seconds: float = 10.0) -> object:
        result = self.call(
            "Runtime.evaluate",
            {
                "expression": expression,
                "returnByValue": True,
                "awaitPromise": True,
                "userGesture": False,
            },
            timeout_seconds=timeout_seconds,
        )
        return result.get("result", {}).get("value")


def log(message: str) -> None:
    print(f"[pi-browser-send] {message}", flush=True)


def fetch_json(url: str) -> object:
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def make_ws_trace_script() -> str:
    return r"""
(() => {
  const trace = [];
  const log = (event, details = {}) => {
    const entry = { event, at: performance.now(), ...details };
    trace.push(entry);
    try { console.log('[ws-trace]', JSON.stringify(entry)); } catch (_) {}
  };
  window.__wsTrace = trace;
  window.__wsTraceDump = () => trace.slice();

  const NativeWebSocket = window.WebSocket;
  function TracedWebSocket(url, protocols) {
    const ws = protocols === undefined ? new NativeWebSocket(url) : new NativeWebSocket(url, protocols);
    log('construct', {
      url: String(url),
      protocols: protocols === undefined ? null : protocols,
      readyState: ws.readyState,
      bufferedAmount: ws.bufferedAmount,
    });
    ws.addEventListener('open', () => {
      log('open', { url: ws.url, readyState: ws.readyState, bufferedAmount: ws.bufferedAmount });
    });
    ws.addEventListener('close', (event) => {
      log('close', {
        url: ws.url,
        code: event.code,
        reason: event.reason,
        wasClean: event.wasClean,
        readyState: ws.readyState,
        bufferedAmount: ws.bufferedAmount,
      });
    });
    ws.addEventListener('error', () => {
      log('error', { url: ws.url, readyState: ws.readyState, bufferedAmount: ws.bufferedAmount });
    });
    ws.addEventListener('message', (event) => {
      const data = typeof event.data === 'string' ? event.data.slice(0, 256) : '[binary]';
      log('message', { url: ws.url, readyState: ws.readyState, bufferedAmount: ws.bufferedAmount, data });
    });
    const nativeSend = ws.send.bind(ws);
    ws.send = (data) => {
      const payload = typeof data === 'string' ? data : null;
      log('send', {
        url: ws.url,
        readyState: ws.readyState,
        bufferedAmountBefore: ws.bufferedAmount,
        payloadLength: payload ? payload.length : (data && data.byteLength) || 0,
        payloadPreview: payload ? payload.slice(0, 256) : '[binary]',
      });
      const result = nativeSend(data);
      log('send-after', {
        url: ws.url,
        readyState: ws.readyState,
        bufferedAmountAfter: ws.bufferedAmount,
      });
      return result;
    };
    return ws;
  }
  TracedWebSocket.prototype = NativeWebSocket.prototype;
  Object.setPrototypeOf(TracedWebSocket, NativeWebSocket);
  window.WebSocket = TracedWebSocket;
})();
""".strip()


def drain_cdp_events(client: CdpClient, duration_seconds: float) -> None:
    deadline = time.monotonic() + duration_seconds
    while time.monotonic() < deadline:
        remaining = max(0.1, deadline - time.monotonic())
        message = client.read_message(timeout_seconds=remaining)
        if not message:
            continue
        method = message.get("method")
        if method and method.startswith("Network.webSocket"):
            log(f"cdp {method}: {json.dumps(message.get('params', {}), separators=(',', ':'))}")
        elif method == "Runtime.consoleAPICalled":
            args = message.get("params", {}).get("args", [])
            values = []
            for arg in args:
                values.append(arg.get("value") if isinstance(arg, dict) else arg)
            log(f"cdp console: {json.dumps(values, separators=(',', ':'))}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--page-url", default="http://sunny-maple.local")
    parser.add_argument("--chromium-bin")
    parser.add_argument("--packet-json")
    parser.add_argument("--packet-file")
    parser.add_argument("--client-id", default="browser-e2e")
    parser.add_argument("--connect-timeout", type=float, default=15.0)
    parser.add_argument("--session-timeout", type=float, default=10.0)
    parser.add_argument("--hold-open", type=float, default=0.5)
    parser.add_argument("--status-url")
    args = parser.parse_args()

    if args.packet_json and args.packet_file:
        parser.error("pass only one of --packet-json and --packet-file")

    if args.packet_file:
        with open(args.packet_file, "r", encoding="utf-8") as handle:
            packet = json.load(handle)
    elif args.packet_json:
        packet = json.loads(args.packet_json)
    else:
        packet = {
            "t": int(time.time() * 1000),
            "seq": 1,
            "btn": {
                "a": 0,
                "b": 0,
                "x": 0,
                "y": 0,
                "lb": 0,
                "rb": 0,
                "back": 0,
                "start": 0,
                "ls": 0,
                "rs": 0,
                "du": 0,
                "dd": 0,
                "dl": 0,
                "dr": 0,
            },
            "ax": {"lx": 0, "ly": 0, "rx": 0, "ry": 0, "lt": 0, "rt": 0},
        }

    chromium_bin = args.chromium_bin
    if not chromium_bin:
        chromium_bin = shutil.which("chromium") or shutil.which("chromium-browser")
    if not chromium_bin:
        raise FileNotFoundError("could not find Chromium binary")

    log(f"using Chromium binary {chromium_bin}")
    log(f"opening page {args.page_url}")
    user_data_dir = tempfile.mkdtemp(prefix="controller-browser-")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind(("127.0.0.1", 0))
            debug_port = probe.getsockname()[1]
        log(f"using remote-debugging-port={debug_port}")
        proc = subprocess.Popen(
            [
                chromium_bin,
                "--headless",
                "--disable-gpu",
                "--no-sandbox",
                "--disable-dev-shm-usage",
                f"--remote-debugging-port={debug_port}",
                f"--user-data-dir={user_data_dir}",
                "about:blank",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            deadline = time.monotonic() + args.connect_timeout
            version = None
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{debug_port}/json/version", timeout=1) as response:
                        version = json.load(response)
                    break
                except Exception:
                    time.sleep(0.1)
            if version is None:
                raise RuntimeError("timed out waiting for Chromium DevTools endpoint")
            log(f"devtools endpoint ready: {version.get('Browser', 'unknown')}")

            list_url = f"http://127.0.0.1:{debug_port}/json/list"
            target = None
            while time.monotonic() < deadline:
                with urllib.request.urlopen(list_url, timeout=1) as response:
                    targets = json.load(response)
                target = next((item for item in targets if item.get("type") == "page"), None)
                if target:
                    break
                time.sleep(0.1)
            if not target:
                raise RuntimeError("timed out waiting for Chromium page target")
                log(f"using page target {target.get('url', 'about:blank')}")

            client = CdpClient(target["webSocketDebuggerUrl"])
            try:
                log("enabling Page and Runtime domains")
                client.call("Page.enable")
                client.call("Runtime.enable")
                client.call("Network.enable")
                client.call("Page.addScriptToEvaluateOnNewDocument", {"source": make_ws_trace_script()})
                log("navigating browser page")
                client.call("Page.navigate", {"url": args.page_url})
                client.wait_for_event("Page.loadEventFired", timeout_seconds=args.connect_timeout)
                log("page load event fired")

                def session_snapshot() -> object:
                    return client.evaluate(
                        "(() => {"
                        "  const gamepad = window.__controllerApp?.gamepadController;"
                        "  return gamepad ? {"
                        "    hasApp: true,"
                        "    wsReady: !!gamepad.ws && gamepad.ws.readyState,"
                        "    connected: !!gamepad.session?.connected,"
                        "    slot: Number.isFinite(gamepad.session?.slot) ? gamepad.session.slot : null,"
                        "    reason: gamepad.session?.reason || 'unknown'"
                        "  } : {hasApp: false};"
                        "})()",
                        timeout_seconds=2.0,
                    )

                deadline = time.monotonic() + args.session_timeout
                snapshot = session_snapshot()
                log(f"initial browser controller snapshot: {json.dumps(snapshot, separators=(',', ':'))}")
                while time.monotonic() < deadline:
                    if snapshot and snapshot.get("connected") and snapshot.get("slot") is not None:
                        break
                    time.sleep(0.2)
                    snapshot = session_snapshot()
                    log(f"browser controller snapshot: {json.dumps(snapshot, separators=(',', ':'))}")
                if not snapshot or not snapshot.get("connected") or snapshot.get("slot") is None:
                    raise RuntimeError(f"browser controller did not connect: {snapshot}")

                packet_js = json.dumps(packet, separators=(",", ":"))
                log(f"sending packet with seq={packet.get('seq')} through browser")
                log(
                    "pre-send websocket snapshot: "
                    + json.dumps(
                        client.evaluate(
                            "(() => {"
                            "  const ws = window.__controllerApp?.gamepadController?.ws;"
                            "  return ws ? {"
                            "    readyState: ws.readyState,"
                            "    bufferedAmount: ws.bufferedAmount,"
                            "    url: ws.url || null"
                            "  } : {readyState: null, bufferedAmount: null, url: null};"
                            "})()",
                            timeout_seconds=2.0,
                        ),
                        separators=(",", ":"),
                    )
                )
                client.evaluate(f"window.__controllerApp.gamepadController.sendPacket({packet_js});", timeout_seconds=5.0)
                log("packet sent through browser")
                drain_cdp_events(client, args.hold_open if args.hold_open > 0 else 0.5)
                if args.hold_open > 0:
                    log(f"holding browser open for {args.hold_open:.2f}s to flush websocket traffic")
                    time.sleep(args.hold_open)
                post_send_trace = client.evaluate(
                    "(() => (window.__wsTraceDump ? window.__wsTraceDump().slice(-20) : []))()",
                    timeout_seconds=2.0,
                )
                log(f"browser websocket trace tail: {json.dumps(post_send_trace, separators=(',', ':'))}")
                log(
                    "post-send websocket snapshot: "
                    + json.dumps(
                        client.evaluate(
                            "(() => {"
                            "  const ws = window.__controllerApp?.gamepadController?.ws;"
                            "  return ws ? {"
                            "    readyState: ws.readyState,"
                            "    bufferedAmount: ws.bufferedAmount,"
                            "    url: ws.url || null"
                            "  } : {readyState: null, bufferedAmount: null, url: null};"
                            "})()",
                            timeout_seconds=2.0,
                        ),
                        separators=(",", ":"),
                    )
                )
                if args.status_url:
                    status = fetch_json(args.status_url)
                    debug = status.get("controller", {}).get("debug", {})
                    log(f"status after send: {json.dumps(debug, separators=(',', ':'))}")
                return 0
            finally:
                client.close()
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    finally:
        shutil.rmtree(user_data_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
