# Hardware Notes

## Recommended Boards

- ESP32-S3 DevKitC-1 is the default developer target.
- ESP32-WROOM-32D dev boards remain supported through the classic `esp32dev` PlatformIO target.
- Classic ESP32 boards have tighter RAM headroom than ESP32-S3 variants, so BLE + Wi-Fi concurrency still needs hardware validation on both targets.

## Host Compatibility

- BLE HID gamepad support varies by host platform and pairing flow.
- ESP32-S3 builds can also target wired USB host modes with `CONTROLLER_HOST_MODE=usb_switch` or `CONTROLLER_HOST_MODE=usb_xinput`.
- `usb_xinput` is intended for Windows PC hosts.

## Power

Use a stable USB power source during BLE + Wi-Fi testing.

## Serial Flashing

- Expected serial ports are typically `/dev/ttyUSB*` or `/dev/ttyACM*` on Linux and `/dev/cu.usbserial-*` on macOS.
- Many USB-to-UART boards auto-reset for flashing, but some require holding `BOOT` while tapping `EN` or `RESET`.

## Integration Checks

- Set `CONTROLLER_BOARD=s3` or `CONTROLLER_BOARD=wroom` to choose the default build, flash, and test target in your shell.
- Set `CONTROLLER_HOST_MODE=ble`, `CONTROLLER_HOST_MODE=usb_switch`, or `CONTROLLER_HOST_MODE=usb_xinput` to choose the host transport where supported.
- Optional local plaintext config can live in `tools/local.env` and is ignored by git. Copy `tools/local.env.example` and set `CONTROLLER_DEFAULT_STA_SSID` / `CONTROLLER_DEFAULT_STA_PASS` to seed saved STA credentials on first boot after a flash/erase.
- `./tools/build_firmware.sh [--board s3|wroom] [--host-mode ble|usb_switch|usb_xinput] [--sta-ssid SSID] [--sta-pass PASS]` builds the selected PlatformIO target.
- `./tools/upload_firmware.sh [--board s3|wroom] [--host-mode ble|usb_switch|usb_xinput] [--sta-ssid SSID] [--sta-pass PASS] [port]` flashes both LittleFS assets and firmware using the repo-local PlatformIO state.
- `./tools/capture_boot_log.sh [port] [seconds]` toggles reset over serial control lines and captures the boot log.
- `./tools/hardware_integration_test.sh [--board s3|wroom] [--sta-ssid SSID] [--sta-pass PASS] [port]` rebuilds, flashes, captures boot logs, and fails if the boot banner is missing or BLE advertising starts before NimBLE host sync.
