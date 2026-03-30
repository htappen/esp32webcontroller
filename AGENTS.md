# Project Plan
# codex resume 019cba78-45f9-7003-ad59-451b095628be
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
   - Persist settings in NVS/Preferences once the hardware path is stable.
   - Verified on hardware that `/dev/ttyACM0` still passes the local startup integration flow after the reliability changes.
   - Verified from `controller-pi` that the direct WebSocket-to-BLE route still passes: neutral packet, button press, axis movement, and timeout-to-neutral.
   - Replaced the Pi-side Playwright path with a lighter Chromium page smoke check because the prior script was injecting JS and synthetic events rather than validating real UI behavior.

9. [NEXT] Get ESP32-S3 BLE pairing/runtime behavior working end to end.
   - Reproduce and root-cause the current Pi-side failure: `org.bluez.Error.ConnectionAttemptFailed: Page Timeout` while pairing to `ESP32 Web Gamepad` on S3.
   - Compare NimBLE/`ESP32-BLE-Gamepad` behavior between WROOM and S3, including advertising/connectability state, address type, and any target-specific init ordering.
   - Add targeted S3-only instrumentation in firmware if needed so the failure can be diagnosed without guessing.
   - Re-run `tools/pi/run_remote_e2e.sh` against the attached S3 until BLE pairing, input event capture, and timeout-to-neutral pass again.

10. [NEXT] Expand automated regression coverage beyond startup smoke tests.
   - Extend `test/host` coverage for mapper/protocol edge cases.
   - Add scripted checks for status endpoints and controller timeout behavior where feasible.

11. Create new SVGs of different controller layouts.
   - Nintendo 64
   - Playstation
   - Xbox
   - Switch
   - Super Nintendo
   - Nintendo
   - Sega Genesis
