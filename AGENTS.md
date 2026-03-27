# Project Plan
# codex resume 019cba78-45f9-7003-ad59-451b095628be
## Current Next Steps

1. [DONE] Retarget firmware from `esp32-s3-devkitc-1` to the classic `ESP32-WROOM-32D` path.
   - `firmware/platformio.ini` now targets `esp32_wroom_32d` with `board = esp32dev`.
   - Build verified with the repo-local PlatformIO core dir and classic ESP32 Xtensa toolchain.
   - Flash usage is high but still fits the default 4 MB / `default.csv` layout.

2. [DONE] Audit USB, BLE, and Wi-Fi compatibility on classic ESP32.
   - The current `ESP32-BLE-Gamepad` path is valid for `architectures=esp32`.
   - No project source depends on S3-only USB APIs; the board uses USB-to-UART successfully.
   - AP/STA assumptions still match the classic ESP32 target at boot.

3. [DONE] Update tooling for the new board.
   - `tools/upload_firmware.sh` and `tools/serial_monitor.sh` now use `/home/htappen/controller/.platformio`.
   - Serial auto-detection covers `/dev/ttyUSB*`, `/dev/ttyACM*`, and common macOS USB-UART names.
   - Hardware docs now mention classic ESP32 serial/reset behavior.

4. [DONE] Rebuild and resolve target-specific compile/runtime issues.
   - Clean PlatformIO builds succeed for `esp32_wroom_32d`.
   - Fixed early BLE advertising startup so boot no longer logs `E NimBLEAdvertising: Host not synced!`.
   - Embedded web UI and WebSocket protocol remain unchanged.

5. [DONE] Flash and validate on attached `ESP32-WROOM-32D` hardware.
   - Verified flashing over `/dev/ttyACM0` on the connected USB-UART board.
   - Captured serial boot logs and confirmed the firmware boot banner on hardware.
   - Auto-reset into the bootloader works on the attached board without manual BOOT/EN intervention.

6. [DONE] Add repeatable hardware integration coverage for the retargeted board.
   - Added `tools/capture_boot_log.sh` and `tools/hardware_integration_test.sh`.
   - `hardware_integration_test.sh` now rebuilds, flashes, captures boot logs, and asserts clean BLE startup.
   - README and hardware docs reference the scripted hardware validation path.

7. [DONE] Document the Raspberry Pi automated host-test route.
   - Added `docs/raspberry-pi-test-plan.md` describing the staged implementation path.
   - Added `docs/raspberry-pi-4-setup.md` with concrete Pi 4 setup and SSH coordination steps.
   - Added `tools/create_pi_ssh_key.sh` to generate the ChromeOS-side SSH key used by the Pi test runner.

8. [DONE] Implement the Raspberry Pi automated end-to-end host test route.
   - Added Pi-side scripts for Wi-Fi AP join, BLE pairing, Linux input capture, WebSocket packet send, and SSH-driven orchestration under `tools/pi/`.
   - Added a Pi-side BlueZ D-Bus pairing agent path (`tools/pi/bluez_pair_gamepad.py`) because non-interactive `bluetoothctl` pairing was not reliable over SSH.
   - Verified on `controller-pi` that the Pi can join `ESP32-Controller`, pair and bond to `ESP32 Web Gamepad`, and expose the BLE host device as `/dev/input/event4`, `/dev/input/js0`, and `/dev/hidraw0`.
   - Verified the local build/flash/startup path still works end to end with `tools/pi/run_remote_e2e.sh` calling the existing hardware integration flow on `/dev/ttyACM0`.
   - Fixed the firmware WebSocket button parser so `0/1` button values are applied correctly before BLE report generation.
   - Verified the direct WebSocket E2E path passes on hardware from `controller-pi`: neutral packet, button press, axis movement, and timeout-to-neutral assertions all pass.
   - Add browser-driven Playwright coverage only after the direct WebSocket E2E path is stable.

9. [DONE] Harden board-specific reliability.
   - Add reconnect/backoff behavior for Wi-Fi and BLE on classic ESP32.
   - Maintain neutral output on disconnect or stalled controller input.
   - Persist settings in NVS/Preferences once the hardware path is stable.
   - Verified on hardware that `/dev/ttyACM0` still passes the local startup integration flow after the reliability changes.
   - Verified from `controller-pi` that the direct WebSocket-to-BLE route still passes: neutral packet, button press, axis movement, and timeout-to-neutral.
   - Replaced the Pi-side Playwright path with a lighter Chromium page smoke check because the prior script was injecting JS and synthetic events rather than validating real UI behavior.

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
