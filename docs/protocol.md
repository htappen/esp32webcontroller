# Protocol

## Controller Packet (JSON)

```json
{
  "t": 1234567,
  "seq": 42,
  "btn": {
    "a": 1,
    "b": 0,
    "x": 0,
    "y": 1,
    "lb": 0,
    "rb": 1,
    "back": 0,
    "start": 0,
    "ls": 0,
    "rs": 0,
    "du": 0,
    "dd": 1,
    "dl": 0,
    "dr": 0
  },
  "ax": {
    "lx": -0.12,
    "ly": 0.84,
    "rx": 0.02,
    "ry": -0.66,
    "lt": 0.30,
    "rt": 0.90
  }
}
```

## Semantics

- Axes are normalized to `[-1.0, 1.0]` for sticks, `[0.0, 1.0]` for triggers.
- `seq` must increase monotonically.
- Firmware drops invalid payloads and can emit debug counters.

## Transport

- Controller stream transport: WebSocket on `ws://game.local:81` by default
- Text frames contain one controller JSON packet per frame.
- On disconnect or packet timeout (`kWsTimeoutMs`), firmware resets to neutral state.

## Control APIs

### `GET /api/status`

```json
{
  "network": {
    "mode": "ap|sta|apsta",
    "apActive": true,
    "staConnected": false,
    "apIp": "<ap-ip>",
    "staIp": "0.0.0.0"
  },
  "host": {
    "advertising": true,
    "connected": false
  },
  "controller": {
    "wsConnected": true,
    "lastPacketAgeMs": 8
  }
}
```

### `POST /api/network/sta`

```json
{
  "ssid": "MyWiFi",
  "pass": "secret"
}
```

### `POST /api/host/pairing`

```json
{
  "enabled": true
}
```
