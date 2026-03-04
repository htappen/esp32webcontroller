# ESP32 Web BLE Controller

ESP32-hosted web controller that runs on a phone and forwards input over WebSocket to firmware, which emits BLE HID gamepad reports to a host.

## Connectivity Model

- Phone connectivity:
  - `AP mode`: ESP32 hosts its own Wi-Fi AP (`ESP32-Controller` by default).
  - `Shared Wi-Fi mode (STA)`: ESP32 joins an existing LAN SSID so phones on that LAN can access it.
  - `AP+STA mode`: keep AP active as fallback while joining shared Wi-Fi.
- Host connectivity:
  - ESP32 advertises as BLE HID gamepad.
  - Host pairs to BLE controller and receives mapped controller reports.

## Layout

- `firmware/`: PlatformIO firmware and embedded web assets.
- `web/`: Optional frontend dev workspace (build output copied into `firmware/data/`).
- `docs/`: Architecture and protocol docs.
- `tools/`: Utility scripts for packing assets and monitoring firmware.
- `test/host/`: Host-side protocol and mapping tests.

## Quick Start

1. Install PlatformIO and ESP32 toolchain.
2. Build firmware:
   - `cd firmware && pio run`
3. Upload filesystem assets:
   - `cd firmware && pio run -t uploadfs`
4. Upload firmware:
   - `cd firmware && pio run -t upload`
5. Sync browser vendor assets from submodules:
   - `./tools/sync_vendor_assets.sh`

## Connection APIs (Scaffold)

- `GET /api/status`:
  - Returns current network mode/AP/STA status and host BLE status.
- `POST /api/network/sta`:
  - Body: `{ "ssid": "...", "pass": "..." }`
  - Stores STA credentials and starts shared Wi-Fi connection attempt.
- `POST /api/host/pairing`:
  - Body: `{ "enabled": true|false }`
  - Enables/disables BLE pairing/discoverable mode.

## Submodules

This repository links upstream dependencies via git submodules:

- `third_party/virtual-gamepad-lib`
- `third_party/ESP32-BLE-Gamepad`

After cloning:

```bash
git submodule update --init --recursive
```
