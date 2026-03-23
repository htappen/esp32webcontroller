# Project Plan
# codex resume 019cba78-45f9-7003-ad59-451b095628be
## Current Next Steps

1. [NEXT] Retarget firmware from `esp32-s3-devkitc-1` to an `ESP32-WROOM-32D` dev board.
   - Replace the PlatformIO board/env with a classic ESP32 target.
   - Re-check flash size, partition layout, upload protocol, and filesystem support.
   - Verify all board-specific assumptions in build flags and libraries.

2. Audit USB, BLE, and Wi-Fi compatibility on classic ESP32.
   - Confirm the current BLE gamepad library path supports non-S3 ESP32 boards.
   - Check whether any code depends on S3-only USB or peripheral behavior.
   - Validate AP/STA networking assumptions against the WROOM-32D target.

3. Update tooling for the new board.
   - Make `tools/upload_firmware.sh` accept the correct upload port flow for the USB-to-UART board.
   - Document expected serial device names and boot/reset behavior.
   - Keep `PLATFORMIO_CORE_DIR=/home/htappen/controller/.platformio` in the scripted path.

4. Rebuild and resolve target-specific compile issues.
   - Run a clean PlatformIO build for the new ESP32 target.
   - Fix library, pin, memory, and partition issues revealed by the retarget.
   - Keep the embedded web UI and WebSocket protocol unchanged unless the target forces changes.

5. Flash and validate on the `ESP32-WROOM-32D` hardware.
   - Upload filesystem and firmware via the scripted flow.
   - Verify serial boot logs, Wi-Fi AP behavior, and web UI availability.
   - Confirm BLE advertising, pairing, and report delivery to the host.

6. Harden board-specific reliability.
   - Add reconnect/backoff behavior for Wi-Fi and BLE on classic ESP32.
   - Maintain neutral output on disconnect or stalled controller input.
   - Persist settings in NVS/Preferences once the hardware path is stable.

7. Add regression coverage for the retargeted board.
   - Expand host-side protocol/mapper tests in `test/host`.
   - Add firmware sanity checks where feasible for parser, status, and telemetry behavior.
