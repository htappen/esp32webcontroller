# Hardware Notes

## Recommended Boards

- ESP32-S3 DevKitC-1 is the default developer target.
- ESP32-WROOM-32D dev boards remain supported through the classic `esp32dev` PlatformIO target.
- Classic ESP32 boards have tighter RAM headroom than ESP32-S3 variants, so BLE + Wi-Fi concurrency still needs hardware validation on both targets.

## Host Compatibility

BLE HID gamepad support varies by host platform and pairing flow.

## Power

Use a stable USB power source during BLE + Wi-Fi testing.

## Serial Flashing

- Expected serial ports are typically `/dev/ttyUSB*` or `/dev/ttyACM*` on Linux and `/dev/cu.usbserial-*` on macOS.
- Many USB-to-UART boards auto-reset for flashing, but some require holding `BOOT` while tapping `EN` or `RESET`.

## Integration Checks

- Set `CONTROLLER_BOARD=s3` or `CONTROLLER_BOARD=wroom` to choose the default build, flash, and test target in your shell.
- `./tools/build_firmware.sh [--board s3|wroom]` builds the selected PlatformIO target.
- `./tools/upload_firmware.sh [--board s3|wroom] [port]` flashes both LittleFS assets and firmware using the repo-local PlatformIO state.
- `./tools/capture_boot_log.sh [port] [seconds]` toggles reset over serial control lines and captures the boot log.
- `./tools/hardware_integration_test.sh [--board s3|wroom] [port]` rebuilds, flashes, captures boot logs, and fails if the boot banner is missing or BLE advertising starts before NimBLE host sync.
