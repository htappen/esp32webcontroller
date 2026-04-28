# Hardware Notes

## Recommended Boards

- ESP32-S3 DevKitC-1 is the default developer target.
- ESP32-WROOM-32D dev boards remain supported through the classic `esp32dev` PlatformIO target.
- Classic ESP32 boards have tighter RAM headroom than ESP32-S3 variants, so BLE + Wi-Fi concurrency still needs hardware validation on both targets.

## Host Compatibility

- BLE HID gamepad support varies by host platform and pairing flow.
- ESP32-S3 builds can also target wired USB host modes with `CONTROLLER_HOST_MODE=usb_switch` or `CONTROLLER_HOST_MODE=usb_xinput`.
- `usb_xinput` is intended for Windows PC hosts and Linux XInput-class host validation.
- The `usb_xinput` firmware path now uses a custom TinyUSB class driver rather than Arduino's generic vendor helper.
- That custom driver is the current implementation direction, but it still needs end-to-end host validation on attached hardware.

## Power

Use a stable USB power source during BLE + Wi-Fi testing.

## Serial Flashing

- Expected serial ports are typically `/dev/ttyUSB*` or `/dev/ttyACM*` on Linux and `/dev/cu.usbserial-*` on macOS.
- S3 flashing uses the ACM port only. If it does not appear, hold `BOOT`, tap `EN` or `RESET`, then release `BOOT` when `/dev/ttyACM*` shows up.
- Many USB-to-UART boards auto-reset for flashing, but some require the manual `BOOT`/`EN` sequence.

## UART Logs For USB Mode

- For ESP32-S3 `usb_switch` and `usb_xinput` debugging, route firmware logs over a separate UART connection to the Raspberry Pi.
- Use the Pi UART pins, typically `GPIO14`/`GPIO15`, and capture logs from the Pi UART device such as `/dev/serial0`.
- This UART log path is for USB-mode runtime debugging only. BLE validation does not need it.
- Enable the logging code with `CONTROLLER_DEBUG_LOGS=1`; in that build mode the Pi USB tests should fail if no UART output is captured.
- The Pi E2E tests now expect runtime UART lines for websocket connect, session assignment, packet apply, and disconnect. If the log is blank, treat it as a logging problem first.
- When capturing those S3 UART logs, skip the extra post-upload watchdog reboot so the board boots the app after flashing instead of staying in ROM download mode.
- If the UART shows repeated reset banners, brownouts, or panic output, inspect [`firmware/platformio.ini`](/home/htappen/controller/firmware/platformio.ini) first. The S3 USB-mode envs should keep the `esp32s3` MCU setting, 4 MB flash sizing, `BOARD_HAS_PSRAM`, and the USB startup flags aligned with the selected host mode before you chase app code.

## WROOM Serial Logs

- For ESP32-WROOM BLE debugging, capture the board's USB-UART bridge instead of the Pi GPIO UART.
- The Pi-side serial device is usually `/dev/ttyUSB*`, and Pi tests can override or pin that path with `PI_SERIAL_PORT`.
- Enable the logging code with `CONTROLLER_DEBUG_LOGS=1`; in that build mode the WROOM BLE tests should fail if no serial output is captured.

## Integration Checks

- Set `CONTROLLER_BOARD=s3` or `CONTROLLER_BOARD=wroom` to choose the default build, flash, and test target in your shell.
- Set `CONTROLLER_HOST_MODE=ble`, `CONTROLLER_HOST_MODE=usb_switch`, or `CONTROLLER_HOST_MODE=usb_xinput` to choose the host transport where supported.
- Optional local plaintext config can live in `tools/local.env` and is ignored by git. Copy `tools/local.env.example` and set `CONTROLLER_DEFAULT_STA_SSID` / `CONTROLLER_DEFAULT_STA_PASS` to seed saved STA credentials on first boot after a flash/erase.
- `./tools/build_firmware.sh [--board s3|wroom] [--host-mode ble|usb_switch|usb_xinput] [--sta-ssid SSID] [--sta-pass PASS]` builds the selected PlatformIO target.
- `./tools/upload_firmware.sh [--board s3|wroom] [--host-mode ble|usb_switch|usb_xinput] [--sta-ssid SSID] [--sta-pass PASS] [port]` flashes both LittleFS assets and firmware using the repo-local PlatformIO state. On S3, it expects the board to already be in ROM download mode on `/dev/ttyACM*`.
- `./tools/capture_boot_log.sh [port] [seconds]` toggles reset over serial control lines and captures the boot log.
- `./tools/hardware_integration_test.sh [--board s3|wroom] [--sta-ssid SSID] [--sta-pass PASS] [port]` rebuilds, flashes, captures boot logs, and fails if the boot banner is missing or BLE advertising starts before NimBLE host sync.

## USB XInput Notes

- `firmware/src/usb_xinput_gamepad.cpp` now registers a TinyUSB app driver through `usbd_app_driver_get_cb()`.
- The driver owns descriptor callbacks, parses the reserved Xbox 360 interface block in `open()`, opens endpoints directly, primes OUT transfers, and sends reports with `usbd_edpt_xfer()`.
- If Linux still rejects `SET_CONFIGURATION`, debug the custom driver behavior and physical USB path first rather than reverting to Arduino's old `USB_INTERFACE_VENDOR` helper path.
