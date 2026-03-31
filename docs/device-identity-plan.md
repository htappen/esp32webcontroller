# Device Identity Plan

## Goals

- Generate per-build device naming from a UUID rather than fixed firmware constants.
- Keep firmware runtime simple by compiling the resolved identity in as preprocessor macros.
- Keep test automation stable with one committed default test UUID.
- Persist the resolved identity to a predictable artifact file so later steps can reuse the exact same names.

## Plan

1. Add a shared identity helper in `tools/lib/device_identity.sh`.
   - Commit one repo-wide default test UUID there.
   - Vendor a curated short-word subset of the `python-petname` English adjective and noun lists there or alongside it.
   - Implement deterministic UUID to two-word petname-style name mapping.
   - Expose helpers for:
   - resolving the active UUID from `--device-uuid`, `CONTROLLER_DEVICE_UUID`, or the committed test UUID
   - deriving `friendly_name`, `ap_ssid`, `ble_name`, `hostname`, and `mdns_instance_name`
   - reading and writing a predictable identity artifact file

2. Persist the resolved identity to a predictable artifact file for reuse across steps.
   - Build can generate a fresh UUID when none is supplied.
   - The resolved UUID and all derived names get written to a small predictable artifact file.
   - Later steps like upload and tests can reuse the same exact identity instead of regenerating a different one.

3. Inject identity into firmware as compile-time macros rather than generating a header.
   - Pass values into PlatformIO and define:
   - `CONTROLLER_DEVICE_UUID`
   - `CONTROLLER_AP_SSID`
   - `CONTROLLER_BLE_NAME`
   - `CONTROLLER_HOSTNAME`
   - `CONTROLLER_MDNS_INSTANCE_NAME`
   - Firmware consumes those macros in `firmware/src/config.h` as compile-time constants.

4. Refactor firmware to consume compile-time identity macros.
   - Replace fixed naming constants in `firmware/src/config.h`.
   - Keep Wi-Fi, BLE, and mDNS call sites unchanged except for using the new compile-time values.
   - Add a compile-time constant for the resolved UUID so it can be surfaced in logs and status.

5. Surface identity in firmware outputs and UI.
   - Add UUID, friendly name, and hostname to boot logs.
   - Extend `/api/status` to report the active generated naming values.
   - Update the web UI to show the device's friendly name and `.local` hostname clearly.

6. Standardize tooling around the identity helper.
   - Update build, upload, erase, local hardware tests, and Pi E2E scripts to use `tools/lib/device_identity.sh`.
   - Tests default to the committed test UUID unless overridden.
   - Build can either use an explicit UUID, the test default, or generate a fresh UUID and persist it.

7. Keep test scripts overrideable, but make static defaults come from shared identity logic.
   - Existing script env vars like `AP_SSID`, `BLE_NAME`, and `MDNS_HTTP_BASE_URL` still work.
   - When not overridden, they resolve from the shared UUID-based identity helper rather than hard-coded literal names.

8. Verify both the static/default path and autodiscovery path.
   - Static/default assertions remain the main test path.
   - Add checks that `/api/status` reports the expected generated names.
   - Add checks that the reported `.local` hostname resolves and serves the same status payload as the raw IP path.

9. Update documentation.
   - Document the UUID-driven naming model, default test UUID, override knobs, and artifact file behavior in `README.md` and relevant hardware/test docs.
   - Replace references to fixed names like `ESP32-Controller`, `ESP32 Web Gamepad`, and `game.local` with the UUID-derived `Pad` naming model where they are no longer universally correct.

10. Preserve current workflow expectations.
   - The committed UUID is only the default for testing and stable local automation.
   - Production or ad hoc builds can generate a fresh UUID automatically.
   - Firmware still ends up with plain compile-time constants, not runtime generation logic or persisted onboard state.
