# ESP32 Web BLE Controller

ESP32-hosted web controller that runs on a phone and forwards input over WebSocket to firmware, which emits BLE HID gamepad reports to a host.

## Connectivity Model

- Phone connectivity:
  - `AP mode`: ESP32 hosts its own Wi-Fi AP (derived from the build UUID).
  - `Shared Wi-Fi mode (STA)`: ESP32 joins an existing LAN SSID so phones on that LAN can access it.
  - `AP+STA mode`: keep AP active as fallback while joining shared Wi-Fi.
- Host connectivity:
  - ESP32 advertises as BLE HID gamepad.
  - Host pairs to BLE controller and receives mapped controller reports.
- Controller data path:
  - Browser sends controller packets via WebSocket to `ws://<device-hostname>.local:81` when the controller is opened by hostname.

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
4. Sync the web UI bundle into `firmware/data/`:
   - `./tools/sync_web_assets.sh`
5. Install PlatformIO and ESP32 toolchain.
6. Select the default board target for your shell:
   - `export CONTROLLER_BOARD=s3`
   - Use `export CONTROLLER_BOARD=wroom` for classic ESP32-WROOM-32D boards.
7. Build firmware:
   - `./tools/build_firmware.sh`
   - One-off override: `./tools/build_firmware.sh --board wroom`
   - One-off UUID override: `./tools/build_firmware.sh --device-uuid 019cba78-45f9-7003-ad59-451b095628be`
8. Upload filesystem assets and firmware:
   - `./tools/upload_firmware.sh /dev/ttyUSB0`
   - One-off override: `./tools/upload_firmware.sh --board wroom /dev/ttyUSB0`
   - One-off UUID override: `./tools/upload_firmware.sh --device-uuid 019cba78-45f9-7003-ad59-451b095628be /dev/ttyUSB0`
8. Upload firmware:
   - The script uploads both LittleFS assets and firmware for the selected board target.
9. Run the hardware startup integration check on an attached board:
   - `./tools/hardware_integration_test.sh /dev/ttyUSB0`
   - One-off override: `./tools/hardware_integration_test.sh --board wroom /dev/ttyUSB0`

## End User Guide

Use this section if the board is already flashed and you just want to connect and play.

### What The Device Does

- Your phone connects to the ESP32 over Wi-Fi and opens the controller page.
- Your game host pairs to the ESP32 over Bluetooth as a gamepad.
- The ESP32 bridges phone input to the host as a BLE controller.

### Device Names

- Wi-Fi network: `<Adjective> <Noun> Pad`
- Wi-Fi security: open network, no password
- Controller page: `http://<adjective>-<noun>.local`
- Bluetooth controller name: `<Adjective> <Noun> Pad`

Builds derive these names from a UUID using a curated short-word subset of the `python-petname` English lists. Test automation defaults to the committed test UUID `019cba78-45f9-7003-ad59-451b095628be`. The most recent build identity is persisted to `build/device_identity.env`.

### Connect And Play

1. Power the flashed ESP32 board over USB.
2. On the device you want to control, open Bluetooth settings and pair to the advertised `<Adjective> <Noun> Pad`.
3. On your phone, join the Wi-Fi network `<Adjective> <Noun> Pad`.
4. Open a browser on the phone and go to the `.local` hostname shown in the web UI or boot log.
5. Wait for the controller page to load, then keep that tab open and in the foreground while you play.
6. Use the on-screen controls on the phone; the paired host should receive them as a Bluetooth gamepad.

### Shared Wi-Fi Option

If the device has already been configured for a local Wi-Fi network, your phone may be able to open the controller page over that network instead of joining the AP. Try the device's `.local` hostname first. If that network does not resolve mDNS reliably, use the IP address shown by whoever configured the board.

### Troubleshooting

- If the host does not see the controller, remove the old Bluetooth pairing for the current `<Adjective> <Noun> Pad`, power-cycle the ESP32, and pair again.
- If the phone says the page cannot be reached, make sure it is still connected to the current device AP and try the device's `.local` hostname again.
- If controls stop responding, refresh the page on the phone and reconnect the Bluetooth controller if needed.
- Keep only one phone connected to the controller page at a time for predictable behavior.

## Connection APIs (Scaffold)

- `GET /api/status`:
  - Returns current network mode/AP/STA status, host BLE status, and WebSocket controller status.
- `POST /api/network/sta`:
  - Body: `{ "ssid": "...", "pass": "..." }`
  - Stores STA credentials and starts shared Wi-Fi connection attempt.

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
