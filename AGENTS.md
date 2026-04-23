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

Board and use-case guidance:

- Use `CONTROLLER_BOARD=wroom` with `CONTROLLER_HOST_MODE=ble` for the classic Bluetooth gamepad path.
- Use `CONTROLLER_BOARD=s3` with `CONTROLLER_HOST_MODE=usb_xinput` for Windows/XInput-style wired USB host mode.
- Use `CONTROLLER_BOARD=s3` with `CONTROLLER_HOST_MODE=usb_switch` for the Switch-oriented USB mode.
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
- If no serial port is available on S3, the script can fall back to the no-button recovery and GPIO-JTAG flashing helpers already in `tools/pi/`.

Complete S3 recovery and flash sequence:

1. If the board is still running firmware and reachable over Wi-Fi, request a clean firmware reboot first:

```bash
./tools/pi/reboot_s3_over_http.sh http://<device-hostname>.local
```

2. If the board does not come back on serial, try the no-button recovery flow:

```bash
CONTROLLER_BOARD=s3 ./tools/pi/recover_s3_without_button.sh
```

3. If serial flashing requires ROM download mode on your hardware, enter flash mode by holding the board `BOOT` button low, then tap `EN` or `RESET`, then release `BOOT` after the serial port appears.

4. Flash the image:

```bash
./tools/upload_firmware.sh --board s3 --host-mode usb_xinput /dev/ttyACM0
```

5. For a direct prebuilt write with optional erase:

```bash
ERASE_FIRST=1 ./tools/write_prebuilt_firmware.sh --board s3 --host-mode usb_xinput /dev/ttyACM0
```

Clarification: this repo currently provides scripted Pi helpers for HTTP reboot and for forcing Pi `GPIO3`/`GPIO4` low during the S3 GPIO-JTAG path, but it does not currently provide a dedicated repo helper that drives board `GPIO0` low for ROM flashing. In the supported workflow here, entering flash mode is still the board-side `BOOT`/`EN` action unless you have separate external wiring for that strap.

If a full local smoke pass is needed, use:

```bash
./tools/hardware_integration_test.sh --board s3 /dev/ttyACM0
./tools/hardware_integration_test.sh --board wroom /dev/ttyUSB0
```

That script rebuilds, flashes, captures the boot log, and checks for startup faults.

## Raspberry Pi Validation

The repo includes Pi-side orchestration for remote build, flash, and end-to-end validation:

```bash
CONTROLLER_BOARD=s3 CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/run_remote_e2e.sh /dev/ttyACM0
CONTROLLER_BOARD=wroom CONTROLLER_HOST_MODE=ble ./tools/pi/run_remote_e2e.sh /dev/ttyUSB0
```

For focused XInput input-event validation on the Pi host:

```bash
./tools/pi/check_xinput_input_events.sh
```

Important Pi-side helpers include:

- `tools/pi/bootstrap_pi.sh` for installing Pi prerequisites
- `tools/pi/recover_s3_without_button.sh` for S3 recovery without physical button access
- `tools/pi/wait_for_acm_then_upload.sh` for rapid reflashing during short S3 ACM windows
- `tools/pi/wait_for_acm_then_write_prebuilt_firmware.sh` and `tools/write_prebuilt_firmware.sh` for direct prebuilt flashing

## Debugging

For ESP32-S3 USB debugging, the preferred path is Raspberry Pi GPIO-JTAG, not the built-in USB JTAG route.

Primary helper:

```bash
CONTROLLER_BOARD=s3 CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/debug_startup_s3.sh
```

This path uses:

- `tools/pi/prepare_s3_gpio_jtag.sh`
- `tools/pi/start_openocd_s3_gpio_jtag.sh`
- `tools/pi/startup_debug.gdb`

Related helpers:

- `tools/pi/debug_attach_noreset_s3.sh`
- `tools/pi/flash_or_debug_s3.sh`
- `tools/pi/reset_s3_watchdog_if_present.sh`
- `tools/pi/set_gpio3_low.sh`
- `tools/pi/set_gpio4_low.sh`

For S3 `usb_xinput` startup debugging, `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` remains the main diagnostic switch when the native USB takeover needs to be delayed.

# Next Steps
