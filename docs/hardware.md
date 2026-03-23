# Hardware Notes

## Recommended Boards

- ESP32-WROOM-32D dev boards over USB-to-UART are the current target.
- The PlatformIO target is `esp32dev`, which matches common 4 MB classic ESP32 dev boards.
- Classic ESP32 boards have tighter RAM headroom than ESP32-S3 variants, so BLE + Wi-Fi concurrency needs validation on hardware.

## Host Compatibility

BLE HID gamepad support varies by host platform and pairing flow.

## Power

Use a stable USB power source during BLE + Wi-Fi testing.

## Serial Flashing

- Expected serial ports are typically `/dev/ttyUSB*` or `/dev/ttyACM*` on Linux and `/dev/cu.usbserial-*` on macOS.
- Many USB-to-UART boards auto-reset for flashing, but some require holding `BOOT` while tapping `EN` or `RESET`.
