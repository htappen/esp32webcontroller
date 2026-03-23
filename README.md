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
- Controller data path:
  - Browser sends controller packets via WebSocket to `ws://<device-ip>:81`.

## Layout

- `firmware/`: PlatformIO firmware and embedded web assets.
- `web/`: Optional frontend dev workspace (build output copied into `firmware/data/`).
- `docs/`: Architecture and protocol docs.
- `tools/`: Utility scripts for packing assets and monitoring firmware.
- `test/host/`: Host-side protocol and mapping tests.

## Quick Start

1. Setup local dev environment:
   - `./tools/setup_env.sh`
2. Install PlatformIO and ESP32 toolchain.
3. Build firmware:
   - `cd firmware && pio run -e esp32_wroom_32d`
4. Upload filesystem assets:
   - `./tools/upload_firmware.sh /dev/ttyUSB0`
5. Upload firmware:
   - The script uploads both LittleFS assets and firmware for the `ESP32-WROOM-32D` target.
6. Open serial monitor if needed:
   - `./tools/serial_monitor.sh /dev/ttyUSB0`
7. Run the hardware startup integration check on an attached board:
   - `./tools/hardware_integration_test.sh /dev/ttyUSB0`
8. Sync browser vendor assets from submodules:
   - `./tools/sync_vendor_assets.sh`

## Connection APIs (Scaffold)

- `GET /api/status`:
  - Returns current network mode/AP/STA status, host BLE status, and WebSocket controller status.
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
