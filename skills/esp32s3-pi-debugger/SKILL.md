---
name: esp32s3-pi-debugger
description: Use when an ESP32-S3 attached to controller-pi needs interactive debugging over the built-in USB JTAG path with OpenOCD and xtensa-esp32s3-elf-gdb instead of serial-print instrumentation.
---

# ESP32-S3 Pi Debugger

Use this skill when the ESP32-S3 is attached to `controller-pi` and serial logging is no longer enough to localize a startup crash or hang.

## Goal

Debug the firmware interactively with the ESP32-S3 built-in USB JTAG interface using OpenOCD + `xtensa-esp32s3-elf-gdb`.

## Preconditions

- The board enumerates on the Pi as Espressif `303a:1001`
- The Pi-side environment has been bootstrapped with:
  - `./tools/pi/bootstrap_pi.sh`
- A recent S3 build exists on the Pi so the ELF and Xtensa GDB binary are available under:
  - `firmware/.pio/build/.../firmware.elf`
  - `.platformio/packages/toolchain-xtensa-esp32s3/bin/xtensa-esp32s3-elf-gdb`

## Standard flow

1. Stage the current repo to the Pi.
2. Flash the target firmware from the Pi.
3. Start OpenOCD on the Pi:
   - `./tools/pi/start_openocd_s3_builtin.sh`
4. Launch GDB on the Pi:
   - `CONTROLLER_BOARD=s3 CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/debug_startup_s3.sh`
5. Set or adjust breakpoints based on the failure boundary.
6. Step with `next`, `step`, `finish`, `bt`, `info locals`, `info registers`.
7. Stop OpenOCD when done:
   - `./tools/pi/stop_openocd_s3_builtin.sh`

## Default breakpoints

The provided startup script breaks at:

- `setup`
- `NetworkManager::begin`
- `HostConnectionManager::begin`
- `WebServerBridge::begin`
- `UsbXInputGamepadBridge::begin`

These are the right first breakpoints for early bring-up failures.

## Notes

- Prefer the debugger over temporary print instrumentation once the board is stable enough to expose built-in JTAG.
- If the board re-enumerates on a different `/dev/ttyACM*` node after flashing, that does not affect OpenOCD; JTAG selection is based on the USB JTAG device, not the serial node name.
- If OpenOCD cannot attach, inspect:
  - `/home/controller/controller-pi-e2e/.pi-openocd.log`
