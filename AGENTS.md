# Project Plan

## Current Next Steps

1. [DONE] Implement real BLE host bridge.
   - Replaced stubs in `firmware/src/ble_gamepad.cpp` with `ESP32-BLE-Gamepad` integration.
   - Added real advertise/connect/send-report path.
   - Compile verified with `PLATFORMIO_CORE_DIR=/home/htappen/controller/.platformio ./.venv/bin/pio run -d firmware`.

2. [DONE] Wire `virtual-gamepad-lib` into the embedded phone UI.
   - Updated `firmware/data/app.js` to emit real button/axis state.
   - Split frontend logic into separate module files:
     - `firmware/data/gamepad_controller.js`
     - `firmware/data/page_state_controller.js`
     - thin bootstrap in `firmware/data/app.js`
   - Refactored `app.js` to class-based design:
     - `PageStateController` for page/network/host state and controls.
     - `GamepadController` for virtual gamepad and WebSocket input streaming.
   - Kept JSON packet schema (`btn`, `ax`, `seq`, `t`).

3. [NEXT] Build and flash firmware + filesystem.
   - `source /home/htappen/controller/.venv/bin/activate`
   - `cd /home/htappen/controller/firmware && pio run -t uploadfs && pio run -t upload`

4. Validate end-to-end behavior on hardware.
   - Phone connects via AP or shared STA network.
   - UI loads and `/api/status` shows `controller.wsConnected=true` when active.
   - Host pairs over BLE and receives mapped input.

5. Harden connectivity.
   - Persist STA credentials in NVS/Preferences.
   - Add STA and BLE reconnect/backoff behavior.
   - Maintain neutral fail-safe on WS/BLE loss.

6. Add regression checks.
   - Expand host-side protocol/mapper tests in `test/host`.
   - Add firmware parser/telemetry sanity checks.
