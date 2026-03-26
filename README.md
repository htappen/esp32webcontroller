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
  - Browser sends controller packets via WebSocket to `ws://game.local:81` when the controller is opened by hostname.

## Layout

- `firmware/`: PlatformIO firmware and embedded web assets.
- `web/`: Optional frontend dev workspace (build output copied into `firmware/data/`).
- `docs/`: Architecture and protocol docs.
- `tools/`: Utility scripts for packing assets and monitoring firmware.
- `test/host/`: Host-side protocol and mapping tests.

## Quick Start

1. Setup local dev environment:
   - `./tools/setup_env.sh`
2. Initialize git submodules:
   - `git submodule update --init --recursive`
3. Sync browser vendor assets from submodules:
   - `./tools/sync_vendor_assets.sh`
4. Install PlatformIO and ESP32 toolchain.
5. Build firmware:
   - `cd firmware && pio run -e esp32_wroom_32d`
6. Upload filesystem assets:
   - `./tools/upload_firmware.sh /dev/ttyUSB0`
7. Upload firmware:
   - The script uploads both LittleFS assets and firmware for the `ESP32-WROOM-32D` target.
8. Run the hardware startup integration check on an attached board:
   - `./tools/hardware_integration_test.sh /dev/ttyUSB0`

## End User Guide

Use this section if the board is already flashed and you just want to connect and play.

### What The Device Does

- Your phone connects to the ESP32 over Wi-Fi and opens the controller page.
- Your game host pairs to the ESP32 over Bluetooth as a gamepad.
- The ESP32 bridges phone input to the host as a BLE controller.

### Default Device Names

- Wi-Fi network: `ESP32-Controller`
- Wi-Fi security: open network, no password
- Controller page: `http://game.local`
- Bluetooth controller name: `ESP32 Web Gamepad`

### Connect And Play

1. Power the flashed ESP32 board over USB.
2. On the device you want to control, open Bluetooth settings and pair to `ESP32 Web Gamepad`.
3. On your phone, join the Wi-Fi network `ESP32-Controller`.
4. Open a browser on the phone and go to `http://game.local`.
5. Wait for the controller page to load, then keep that tab open and in the foreground while you play.
6. Use the on-screen controls on the phone; the paired host should receive them as a Bluetooth gamepad.

### Shared Wi-Fi Option

If the device has already been configured for a local Wi-Fi network, your phone may be able to open the controller page over that network instead of joining `ESP32-Controller`. Try `http://game.local` first. If that network does not resolve mDNS reliably, use the IP address shown by whoever configured the board.

### Troubleshooting

- If the host does not see the controller, remove the old Bluetooth pairing for `ESP32 Web Gamepad`, power-cycle the ESP32, and pair again.
- If the phone says the page cannot be reached, make sure it is still connected to `ESP32-Controller` and try `http://game.local` again.
- If controls stop responding, refresh the page on the phone and reconnect the Bluetooth controller if needed.
- Keep only one phone connected to the controller page at a time for predictable behavior.

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

Then sync the browser assets used by the embedded web UI:

```bash
./tools/sync_vendor_assets.sh
```

The repo intentionally does not track copied vendor output under `firmware/data/vendor/`.
If you need to rebuild the submodule's dist files first, run:

```bash
./tools/sync_vendor_assets.sh --build
```
