# Project Overview

This repository contains an ESP32-based web-controlled gamepad project. The firmware hosts a web UI and WebSocket bridge, translates browser input into a transport-neutral host report, and then presents that report to a host over either BLE or USB depending on board and host mode.

The main supported targets are:

- `CONTROLLER_BOARD=wroom` for the classic ESP32 BLE path
- `CONTROLLER_BOARD=s3` for the ESP32-S3 path

The main host modes are:

- `CONTROLLER_HOST_MODE=ble`
- `CONTROLLER_HOST_MODE=usb_xinput`
- `CONTROLLER_HOST_MODE=usb_switch`

Defaults in the current tooling are aimed at the S3 workflow. Most scripts resolve the board, PlatformIO environment, serial port, and device identity automatically.

## Environment Note

For this workspace, assume the physical ESP32-S3 board is connected to the Raspberry Pi, not the local workstation running Codex.

- Prefer Pi-side flash/debug/test flows for S3 hardware work.
- Do not assume `/dev/ttyACM*` will appear on the local machine.
- For USB-mode S3 runtime logs, use the Raspberry Pi UART wiring and capture logs from the Pi UART device, not from `/dev/ttyACM*`. BLE-only validation does not need the UART log path.
- Set `CONTROLLER_DEBUG_LOGS=1` when you want the firmware to compile in debug logging. In that mode, Pi USB tests should assert that UART logging is actually present, and WROOM BLE tests should capture the board's USB-UART serial port.
- When a task needs flashing or hardware validation, use the Pi helpers in `tools/pi/` first.
- If manual button timing is needed for ROM download mode, start the appropriate wait/upload helper and then ask the user to press `BOOT`/`EN`.

Board and use-case guidance:

- Use `CONTROLLER_BOARD=wroom` with `CONTROLLER_HOST_MODE=ble` for the classic Bluetooth gamepad path.
- Use `CONTROLLER_BOARD=s3` with `CONTROLLER_HOST_MODE=usb_xinput` for Windows/XInput-style wired USB host mode.
- Use `CONTROLLER_BOARD=s3` with `CONTROLLER_HOST_MODE=usb_switch` for the Switch-oriented USB mode.
- Treat `usb_switch` as a multi-controller transport, same as `usb_xinput`: preserve `sendSlots()` semantics and per-slot USB enumeration when changing this path.
- Use `CONTROLLER_BOARD=s3` with `CONTROLLER_HOST_MODE=ble` only when specifically validating BLE behavior on S3.

# Build, Flash, And Debug

## Environment Setup

Use the provided setup script to create the Python virtualenv, install PlatformIO, and install web dependencies:

```bash
./tools/setup_env.sh
source .venv/bin/activate
```

Optional local configuration can live in:

- `tools/local.env`
- `tools/pi/local.env`

Useful environment variables:

- `CONTROLLER_BOARD=s3|wroom`
- `CONTROLLER_HOST_MODE=ble|usb_xinput|usb_switch`
- `CONTROLLER_DEVICE_UUID=<uuid>`
- `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` for S3 `usb_xinput` diagnostics

## Build

Build the firmware with the script wrapper rather than calling PlatformIO directly:

```bash
./tools/build_firmware.sh --board s3 --host-mode usb_xinput
./tools/build_firmware.sh --board wroom --host-mode ble
```

The build script resolves the correct PlatformIO environment and injects device identity metadata.

## Flash

For normal serial flashing, use:

```bash
./tools/upload_firmware.sh --board s3 --host-mode usb_xinput /dev/ttyACM0
./tools/upload_firmware.sh --board wroom --host-mode ble /dev/ttyUSB0
```

Notes:

- `tools/upload_firmware.sh` uploads the filesystem image first, then firmware, unless `--skip-uploadfs` is passed.
- On S3, the script also requests a post-upload watchdog reset through `tools/reboot_board.sh`.
- Flashing is ACM-only on S3. If `/dev/ttyACM*` is missing, put the board into ROM download mode manually: hold `BOOT`, tap `EN` or `RESET`, then release `BOOT` after the ACM port appears.

Complete S3 recovery and flash sequence:

1. If serial flashing requires ROM download mode on your hardware, enter flash mode by holding the board `BOOT` button low, then tap `EN` or `RESET`, then release `BOOT` after the ACM port appears.

2. Flash the image:

```bash
./tools/upload_firmware.sh --board s3 --host-mode usb_xinput /dev/ttyACM0
```

3. For a direct prebuilt write with optional erase:

```bash
ERASE_FIRST=1 ./tools/write_prebuilt_firmware.sh --board s3 --host-mode usb_xinput /dev/ttyACM0
```

Clarification: the supported flashing workflow uses the board-side `BOOT`/`EN` reset sequence and `/dev/ttyACM*`. GPIO-JTAG remains a debugging path only.

If a full local smoke pass is needed, use:

```bash
./tools/hardware_integration_test.sh --board s3 /dev/ttyACM0
./tools/hardware_integration_test.sh --board wroom /dev/ttyUSB0
```

That script rebuilds, flashes, captures the boot log, and checks for startup faults.

## Raspberry Pi Validation

The ESP32-S3 is connected to the Raspberry Pi for USB host, flash, and debug work. Before Pi-side flashing or validation, make sure the current workspace contents are copied to the Pi repo at `~/controller-pi-e2e`; do not assume the Pi checkout is already current.

The repo includes Pi-side orchestration for remote build, flash, and end-to-end validation:

```bash
CONTROLLER_BOARD=s3 CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/run_remote_e2e.sh /dev/ttyACM0
CONTROLLER_BOARD=wroom CONTROLLER_HOST_MODE=ble ./tools/pi/run_remote_e2e.sh /dev/ttyUSB0
```

If you are running Pi commands manually over SSH instead of `run_remote_e2e.sh`, sync the repo first:

```bash
./tools/pi/sync_repo_to_pi.sh
```

After syncing, make Pi-side shell helpers executable if needed before invoking them manually:

```bash
chmod +x ./tools/pi/*.sh ./tools/pi/*.py
```

For focused XInput input-event validation on the Pi host:

```bash
./tools/pi/check_xinput_input_events.sh
```

Pi-side Python helpers should use the repo-managed venv at `~/controller-pi-e2e/tools/pi/.venv-pi/bin/python`. Do not assume the global `python3`, a host venv, or an activated shell venv is the interpreter running a given helper.

Serial-log guidance:

- For S3 USB-mode runtime logs, use the Pi UART path and `PI_UART_PORT` if you need to override the default `/dev/serial0`.
- For WROOM debug logs, use the board's USB-UART port and `PI_SERIAL_PORT` if you need to override auto-detection.
- In debug mode, Pi tests should fail if the expected serial log path is missing or produces no output.

Important Pi-side helpers include:

- `tools/pi/bootstrap_pi.sh` for installing Pi prerequisites
- `tools/pi/wait_for_acm_then_upload.sh` for rapid reflashing during short S3 ACM windows
- `tools/pi/wait_for_acm_then_write_prebuilt_firmware.sh` and `tools/write_prebuilt_firmware.sh` for direct prebuilt flashing

## Debugging

For ESP32-S3 USB debugging, the preferred path is Raspberry Pi GPIO-JTAG, not the built-in USB JTAG route.
Use GPIO-JTAG when debugging USB transport behavior on S3, especially when the device enumerates but reports do not reach the host or the WebSocket path stops advancing after reboot.
Use the Pi UART for runtime serial logs in USB mode; do not rely on `/dev/ttyACM*` for those logs. BLE mode can keep using the existing serial path if needed.
If GPIO-JTAG fails to attach or the target ends up in a bad state, restart or power-cycle the board before retrying the debug helper. In practice, that usually means a fresh board reset or unplug/replug cycle on the Pi-connected S3.

Primary helper:

```bash
CONTROLLER_BOARD=s3 CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/debug_startup_s3.sh
```

As with Pi-side validation, sync the current workspace to `~/controller-pi-e2e` before starting a Pi-side debug session so OpenOCD/GDB and firmware sources match the code you are investigating.

This path uses:

- `tools/pi/prepare_s3_gpio_jtag.sh`
- `tools/pi/start_openocd_s3_gpio_jtag.sh`
- `tools/pi/startup_debug.gdb`

Related helpers:

- `tools/pi/debug_attach_noreset_s3.sh`
- `tools/pi/reset_s3_watchdog_if_present.sh`
- `tools/pi/set_gpio3_low.sh`
- `tools/pi/set_gpio4_low.sh`

For S3 `usb_xinput` startup debugging, `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` remains the main diagnostic switch when the native USB takeover needs to be delayed.

# Next Steps
