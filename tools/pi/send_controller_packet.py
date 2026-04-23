#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import time
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


def make_close_frame() -> bytes:
    return bytes([0x88, 0x80, 0, 0, 0, 0])


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


def wait_for_session_assignment(sock: socket.socket, timeout_seconds: float) -> dict:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        sock.settimeout(remaining)
        opcode, payload = read_frame(sock)
        if opcode != 1:
            continue
        message = json.loads(payload.decode("utf-8"))
        if message.get("type") != "session":
            continue
        if not message.get("connected"):
            raise RuntimeError(f"controller session rejected: {message}")
        return message
    raise RuntimeError("timed out waiting for controller session assignment")


def open_websocket(url: str) -> socket.socket:
    parsed = urlparse(url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "wss" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path += f"?{parsed.query}"

    raw = socket.create_connection((host, port), timeout=5)
    if parsed.scheme == "wss":
        context = ssl.create_default_context()
        raw = context.wrap_socket(raw, server_hostname=host)

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


def default_packet(seq: int) -> dict:
    return {
        "t": int(time.time() * 1000),
        "seq": seq,
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://192.168.4.1:81")
    parser.add_argument("--packet-json")
    parser.add_argument("--packet-file")
    parser.add_argument("--seq", type=int, default=1)
    parser.add_argument("--hold-open", type=float, default=0.0)
    parser.add_argument("--client-id", default="pi-test-client")
    parser.add_argument("--hello-timeout", type=float, default=3.0)
    args = parser.parse_args()

    if args.packet_json and args.packet_file:
        parser.error("pass only one of --packet-json and --packet-file")

    if args.packet_file:
        with open(args.packet_file, "r", encoding="utf-8") as handle:
            packet = json.load(handle)
    elif args.packet_json:
        packet = json.loads(args.packet_json)
    else:
        packet = default_packet(args.seq)

    packet.setdefault("t", int(time.time() * 1000))
    packet.setdefault("seq", args.seq)

    sock = open_websocket(args.url)
    try:
        hello = {
            "type": "hello",
            "clientId": args.client_id,
            "protocolVersion": 2,
        }
        sock.sendall(make_text_frame(json.dumps(hello, separators=(",", ":")).encode("utf-8")))
        wait_for_session_assignment(sock, args.hello_timeout)
        sock.sendall(make_text_frame(json.dumps(packet, separators=(",", ":")).encode("utf-8")))
        if args.hold_open > 0:
            time.sleep(args.hold_open)
        sock.sendall(make_close_frame())
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
