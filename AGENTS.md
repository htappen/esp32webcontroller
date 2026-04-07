# Project Plan
# codex resume 019cba78-45f9-7003-ad59-451b095628be
## Current State

- The tracked plan is up to date through the UUID-derived device identity work and the BLE host-forget flow.
- The main active work is now the ESP32-S3 `usb_xinput` path for Windows-style wired host mode, including Pi-side flashing and Linux host validation.
- The current worktree includes first-party source edits for `usb_xinput`, Pi-side remote flashing, and USB/XInput test orchestration.
- The transport-separation refactor is partially landed: the mapper emits a transport-neutral `HostInputReport`, the firmware exposes a `HostTransport` abstraction, and status/UI now distinguish Bluetooth vs `USB-PC`/`USB-Switch`.
- The Pi-side remote runner now stages the live worktree correctly, can bootstrap a minimal PlatformIO environment without Node.js, and can reuse prebuilt `firmware/data` assets during remote S3 builds.
- The `usb_xinput` path now has an initial custom TinyUSB class-driver backend in `firmware/src/usb_xinput_gamepad.cpp` that registers via `usbd_app_driver_get_cb`, owns `open`, opens the endpoint set directly, primes OUT transfers, and handles the minimum XInput control requests without `tud_vendor_n_*`.
- The current custom driver is still an initial port, not a validated endpoint-compatible clone of `gp2040-ce`; host acceptance and any remaining auth/control quirks still need real Linux host validation.
- Pi-side flash and reset validation on April 4, 2026 showed the S3 booting from flash (`boot:0x29 (SPI_FAST_FLASH_BOOT)`), but the USB host path still failed to enumerate cleanly as XInput: Linux reported repeated `device descriptor read/all, error -75`, intermittently fell back to `303a:1001`, and never exposed an Xbox input node.
- Espressif's `USB-Serial/JTAG` reset behavior is now a tracked factor for the attached Tenstar S3 board: when flashing over that path, the default post-flash reset can leave the chip in download mode because the boot strap is not re-sampled. The software path to force a normal reboot is `esptool --after watchdog-reset`.
- The reset-button issue is now solved in tooling: Pi-side uploads can finish and trigger a software restart through `esptool --after watchdog_reset`, without requiring a manual EN press.
- The active `usb_xinput` debug path has now shifted away from ad hoc serial breadcrumbs: the Pi environment bootstrap installs `openocd` and `gdb`, and the repo now carries Pi-side OpenOCD/GDB launch helpers for the Raspberry Pi GPIO-to-ESP32-S3 JTAG wiring path instead of the earlier built-in USB-JTAG flow.
- The latest Pi-side validation still showed the attached S3 alternating between `303a:1001` (`Espressif USB JTAG/serial debug unit`) and failed full-speed descriptor reads on the native USB path, so there is still a separate USB reset/path issue to keep in mind during future `usb_xinput` work even though the active debugger path has moved to Raspberry Pi GPIO JTAG.
- The first reflash attempt after adding the watchdog-reset helper did not reach the new path because `/dev/ttyACM0` was already gone before `uploadfs` started; the board was absent from `lsusb`, so the next hardware attempt still requires the port to reappear first.
- The deferred `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` diagnostic build still exists as a fallback path for keeping the board on `USB-Serial/JTAG`, but the temporary constructor/setup and class-driver print instrumentation used during early bring-up has now been removed.
- The current Pi-side GPIO-JTAG path uses Raspberry Pi pins `GPIO11`/`GPIO24`/`GPIO25`/`GPIO7` for `MTCK`/`MTDO`/`MTDI`/`MTMS`, with the repo OpenOCD config in `tools/pi/esp32s3_rpi_gpio_jtag.cfg`.
- The corrected external JTAG wiring plus holding Pi `GPIO3` low during reset now produces a real ESP32-S3 JTAG TAP on the Pi GPIO path; the current stable debugger path is single-core `cpu0` attach with `ESP32_S3_ONLYCPU 1` and GDB `target extended-remote :3333`.
- The current Pi debugger recovery rule is: drive Pi `GPIO3` and `GPIO4` low first, then if `/dev/ttyACM0` or `/dev/ttyACM1` is visible, prefer a software reboot through `esptool --after watchdog_reset` before starting the GPIO-JTAG attach. If no ACM port is stable, fall back to manual board reset with the Pi strap lines already low.
- The latest proved GPIO-JTAG attach against the standalone minimal S3 image now halts cleanly on `cpu0` with a real PC/backtrace, so the active blocker is no longer "can we attach a debugger" but "where does the normal `usb_xinput` startup path fail between `UsbXInputGamepadBridge::begin()`, `xinputUsbInit()`, and `USB.begin()` on fresh deploys."
- A fresh normal `usb_xinput` build/flash/debug loop over Raspberry Pi GPIO JTAG now shows that the firmware is not crashing after native USB takeover: after the USB disappearance, `cpu0` halts cleanly in the idle task, `UsbXInputGamepadBridge` has `started_ = true` and `deferred_start_ = false`, but the custom TinyUSB driver state still has `interfaces_opened = false` with all endpoint addresses at zero. That narrows the failure to host-side enumeration/configuration never reaching the class-driver `open()` path after `USB.begin()`.
- The latest low-level debug pass found a concrete protocol mismatch in the custom XInput device descriptor: `kXbox360DeviceDescriptor.bMaxPacketSize0` was hard-coded to `8` while the ESP32-S3 Arduino TinyUSB stack uses `CFG_TUD_ENDPOINT0_SIZE = 64`. That mismatch is a strong fit for the observed Linux `device descriptor read/all, error -75` failure before config/string/class-driver callbacks. The code is now patched to advertise `CFG_TUD_ENDPOINT0_SIZE` and to fail loudly if `tinyusb_enable_interface()` does not return `ESP_OK`.
- Pi-side OpenOCD/GDB attach is now proven on the attached Tenstar S3. With the normal `usb_xinput` image, the board still falls off USB/JTAG as soon as execution resumes; with `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1`, the board stays present as `303a:1001`, and a post-boot GDB attach lands in the idle task (`esp_pm_impl_waiti` via `prvIdleTask`) instead of crashing or disappearing.
- Deferred-build single-stepping now shows the normal Arduino startup chain on the real board: `app_main` -> `loopTask` -> project `setup()`, then `Serial.begin`, `delay(200)`, `g_state.reset()`, `NetworkManager::begin()`, `HostConnectionManager::begin()`, `WebServerBridge::begin()`, and the later `Serial.printf(...)` lines all become reachable under GDB. That means the deferred path is not failing in early generic startup; the remaining instability is specific to the non-deferred/native-USB runtime path.
- The tighter direct-attach path now proves a lower-level boundary on the normal image too: with the new 10-second pre-`USB.begin()` hold, OpenOCD can finally catch the non-deferred build, but the earliest stable stop is a raw halt at `PC=0x40000400` with no usable stack/register context, and a single `continue` immediately drops the board off the JTAG device again (`LIBUSB_ERROR_NO_DEVICE`). So the non-deferred divergence is even earlier and harsher than the deferred startup path: once resumed from that low-level halt, the board tears down the JTAG link before reaching the usual startup breakpoints.
- Built-in USB JTAG appears to have reached its practical limit for the normal path on this setup. The next immediate probe is now temporary ROM-level instrumentation only at the isolated edge in `UsbXInputGamepadBridge::begin()`: `before xinputUsbInit`, `after xinputUsbInit`, `before USB.begin`, `after USB.begin`, and `begin complete`.

## Current Next Steps

1. [DONE] Support both classic `ESP32-WROOM-32D` and `ESP32-S3` in the firmware build and helper scripts.
   - `firmware/platformio.ini` now defines both `esp32_wroom_32d` and `esp32_s3_devkitc_1`.
   - The default developer target is now `CONTROLLER_BOARD=s3`, with `CONTROLLER_BOARD=wroom` for the classic ESP32 path.
   - Added compile-time board selection via PlatformIO `build_flags` and centralized the firmware-side board gating in `firmware/src/board_config.h`.

2. [DONE] Update build, flash, erase, and test tooling to honor the selected board target.
   - Added shared board/env resolution in `tools/lib/esp32_common.sh`.
   - Added `tools/build_firmware.sh`.
   - Updated `tools/upload_firmware.sh`, `tools/erase_flash.sh`, `tools/hardware_integration_test.sh`, and `tools/pi/run_remote_e2e.sh` to honor `CONTROLLER_BOARD` and optional `--board`.

3. [DONE] Rebuild both targets and verify the board-selection refactor.
   - Clean PlatformIO builds succeed for `esp32_wroom_32d`.
   - Clean PlatformIO builds succeed for `esp32_s3_devkitc_1`.
   - The firmware now exposes the selected board name in boot/status metadata.

4. [DONE] Fix the attached ESP32-S3 flash-layout mismatch discovered during hardware validation.
   - The connected S3 on `/dev/ttyACM0` reports 4 MB embedded flash, not the default 8 MB expected by `esp32-s3-devkitc-1`.
   - `firmware/platformio.ini` now forces `board_upload.flash_size = 4MB` for the S3 environment so flashed images boot on the attached hardware.
   - S3 upload, local AP startup, and `/api/status` now work on the attached board.

5. [DONE] Make the local startup smoke test tolerate ESP32-S3 USB serial behavior.
   - `tools/capture_boot_log.sh` now survives temporary serial disconnect/re-enumeration during S3 reset.
   - `tools/hardware_integration_test.sh` now uses a longer default boot-log window for S3 and treats boot faults, not missing app banners, as the primary S3 startup failure signal.
   - Local S3 startup validation now passes on the attached board.

6. [DONE] Document the Raspberry Pi automated host-test route.
   - Added `docs/raspberry-pi-test-plan.md` describing the staged implementation path.
   - Added `docs/raspberry-pi-4-setup.md` with concrete Pi 4 setup and SSH coordination steps.
   - Added `tools/create_pi_ssh_key.sh` to generate the ChromeOS-side SSH key used by the Pi test runner.

7. [DONE] Implement the Raspberry Pi automated end-to-end host test route for the classic ESP32 path.
   - Added Pi-side scripts for Wi-Fi AP join, BLE pairing, Linux input capture, WebSocket packet send, and SSH-driven orchestration under `tools/pi/`.
   - Added a Pi-side BlueZ D-Bus pairing agent path (`tools/pi/bluez_pair_gamepad.py`) because non-interactive `bluetoothctl` pairing was not reliable over SSH.
   - Verified on `controller-pi` that the Pi can join `ESP32-Controller`, pair and bond to `ESP32 Web Gamepad`, and expose the BLE host device as `/dev/input/event4`, `/dev/input/js0`, and `/dev/hidraw0`.
   - Verified the local build/flash/startup path still works end to end with `tools/pi/run_remote_e2e.sh` calling the existing hardware integration flow on `/dev/ttyACM0`.
   - Fixed the firmware WebSocket button parser so `0/1` button values are applied correctly before BLE report generation.
   - Verified the direct WebSocket E2E path passes on hardware from `controller-pi`: neutral packet, button press, axis movement, and timeout-to-neutral assertions all pass.
   - Add browser-driven Playwright coverage only after the direct WebSocket E2E path is stable.

8. [DONE] Harden board-specific reliability.
   - Add reconnect/backoff behavior for Wi-Fi and BLE on classic ESP32.
   - Maintain neutral output on disconnect or stalled controller input.
   - Persist runtime settings in NVS/Preferences once the hardware path is stable.
   - Verified on hardware that `/dev/ttyACM0` still passes the local startup integration flow after the reliability changes.
   - Verified from `controller-pi` that the direct WebSocket-to-BLE route still passes: neutral packet, button press, axis movement, and timeout-to-neutral.
   - Replaced the Pi-side Playwright path with a lighter Chromium page smoke check because the prior script was injecting JS and synthetic events rather than validating real UI behavior.

9. [DONE] Add device identity propagation and BLE host-management controls.
   - Added shared UUID-derived identity resolution in `tools/lib/device_identity.sh` and threaded it through build, upload, local hardware test, and Pi E2E tooling.
   - Firmware now exposes board and identity metadata via boot logs and `/api/status`, including UUID, friendly name, hostname, and `.local` URL.
   - Added the `/api/host/forget` API and UI action to drop the current BLE host bond so another device can pair.
   - Pi-side E2E scripts now assert the resolved identity consistently across direct-IP, mDNS, and autodiscovery flows.

10. [NEXT] Validate `usb_xinput` end to end from the Raspberry Pi host path.
   - [DONE] Stop iterating on Arduino's generic vendor helper path for `usb_xinput`; the firmware now registers a custom TinyUSB app driver and no longer routes XInput report traffic through `tud_vendor_n_*`.
   - [DONE] Port the first `gp2040-ce`-style class-driver skeleton toward ESP32-S3: own the device/config/string descriptor callbacks, parse the reserved XInput subdescriptors in `open`, open the endpoints directly, and handle IN/OUT transfers in the custom driver.
   - [DONE] Teach the Pi/local reboot helper to use `esptool --after watchdog-reset` for `ESP32-S3`, so software-triggered resets can leave download mode without always requiring a manual EN press on the Tenstar board.
   - [DONE] Add a diagnostic `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` build mode so `usb_xinput` can boot and stay on `USB-Serial/JTAG` long enough to keep the JTAG/serial path available during startup experiments.
   - Reuse more of the upstream raw descriptor tables, control behavior, and endpoint semantics where practical if Linux host validation still shows mismatches.
   - Treat the `gp2040-ce` auth/control path as a reference, not a drop-in dependency. Port only the minimum control-transfer behavior needed for Linux/XInput host acceptance first, then decide whether fuller auth handling is required.
   - Re-run Pi-side host validation with the new custom driver and only then revisit descriptor-level mismatches if Linux still rejects `SET_CONFIGURATION`.
   - Keep the separate physical-path sanity check in place during re-test: ensure the S3 OTG/device USB path is connected to the host and that the board is reset into normal firmware mode rather than ROM download mode before interpreting host results.
   - [DONE] Reflash with `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` and verify that the board remains on `USB-Serial/JTAG` after software reboot, proving native USB takeover can be removed from the immediate debug path.
   - [DONE] Remove the temporary serial/ROM breadcrumb instrumentation after it narrowed the startup boundary enough to justify switching tools.
   - [DONE] Add Pi-side debugger support: `tools/pi/bootstrap_pi.sh` now installs OpenOCD/GDB prerequisites, and the repo now includes the Raspberry Pi GPIO JTAG OpenOCD config and helpers: `tools/pi/esp32s3_rpi_gpio_jtag.cfg`, `tools/pi/prepare_s3_gpio_jtag.sh`, `tools/pi/set_gpio3_low.sh`, `tools/pi/set_gpio4_low.sh`, `tools/pi/start_openocd_s3_gpio_jtag.sh`, `tools/pi/stop_openocd_s3_gpio_jtag.sh`, `tools/pi/debug_startup_s3.sh`, and `tools/pi/startup_debug.gdb`.
   - [DONE] Attach OpenOCD + `xtensa-esp32s3-elf-gdb` to the built-in S3 JTAG path during the post-flash reboot window and confirm the difference between the normal and deferred `usb_xinput` images: the normal image still tears down USB/JTAG on resume, while the deferred image remains debuggable and reaches a live idle-task state.
   - [DONE] Refine the deferred-build debugger path to use earlier startup anchors (`app_main`, `loopTask`, then `setup()`), and verify under GDB that deferred startup reaches `NetworkManager::begin()`, `HostConnectionManager::begin()`, `WebServerBridge::begin()`, and the later setup-side `Serial.printf(...)` calls.
   - [DONE] Add a temporary longer non-deferred pre-`USB.begin()` hold and replace the one-shot Pi attach flow with a retrying OpenOCD path so the normal image can be caught at all over built-in JTAG.
   - [DONE] Confirm from the ESP32-S3 Xtensa toolchain that `PC=0x40000400` is the reset vector, so `monitor reset halt` lands below the app path we actually need to observe.
   - [DONE] Try no-reset and retrying OpenOCD attach flows against the normal image's 10-second pre-`USB.begin()` window; these improve capture reliability, but built-in USB JTAG still does not provide a stable step-through path across the native USB handoff.
   - [DONE] Run a fresh build/flash/debug loop on the normal `usb_xinput` image using the proven Raspberry Pi GPIO-JTAG path. Result: the app survives through `USB.begin()`, but the custom XInput driver never reaches `open()`/endpoint assignment, so the next debug step is descriptor/control-path instrumentation around enumeration rather than crash chasing.

11. [NEXT] Get ESP32-S3 BLE pairing/runtime behavior working end to end.
   - Reproduce and root-cause the current Pi-side failure: `org.bluez.Error.ConnectionAttemptFailed: Page Timeout` while pairing to `ESP32 Web Gamepad` on S3.
   - Compare NimBLE/`ESP32-BLE-Gamepad` behavior between WROOM and S3, including advertising/connectability state, address type, and any target-specific init ordering.
   - Add targeted S3-only instrumentation in firmware if needed so the failure can be diagnosed without guessing.
   - Re-run `tools/pi/run_remote_e2e.sh` against the attached S3 until BLE pairing, input event capture, and timeout-to-neutral pass again.

12. [NEXT] Add USB host-connected controller mode for supported ESP32 boards.
   - [DONE] Keep the web/state path shared, introduce a transport-neutral host report, and isolate BLE vs USB behavior behind a `HostTransport` interface.
   - Treat `ESP32-S3` as the primary USB implementation target and keep classic `ESP32-WROOM-32D` on the BLE-only path unless external USB hardware is added.
   - For `USB-PC`/`usb_xinput`, prefer a dedicated custom TinyUSB class-driver backend modeled on `gp2040-ce` rather than extending Arduino's generic vendor helper.
   - Start with `USB-Switch` on S3, then decide whether `USB-PC` should be a second transport variant or share the same USB backend with different descriptors.
   - Keep the end-to-end testing model aligned with the refactor plan: shared scenario logic, transport-specific host probes, and USB validation with the ESP32 attached to the developer workstation while the Pi still drives the web path.

13. [NEXT] Expand automated regression coverage beyond startup smoke tests.
   - Extend `test/host` coverage for mapper/protocol edge cases.
   - Add scripted checks for status endpoints and controller timeout behavior where feasible.

14. Create new SVGs of different controller layouts.
   - Nintendo 64
   - Playstation
   - Xbox
   - Switch
   - Super Nintendo
   - Nintendo
   - Sega Genesis
