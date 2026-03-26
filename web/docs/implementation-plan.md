# Implementation Plan

This plan is based on the requirements in `web/docs/requirements.md` and the current firmware/web scaffold in the repository.

## Goals

1. Persist working Wi-Fi credentials on the ESP32 without reflashing firmware.
2. Keep the normal user experience focused on the gamepad, with configuration hidden behind a modal.
3. Split configuration responsibilities correctly:
   1. Device configuration lives on the ESP32.
   2. Controller layout configuration lives in browser cookies on the client device.
4. Preserve the previous working Wi-Fi credentials until a newly entered network has been verified.
5. Stop broadcasting the ESP32 access point once a shared Wi-Fi connection succeeds.
6. Add a secrets-safe test path that verifies AP fallback, STA success, and failed credential updates without committing Wi-Fi credentials to git.

## Proposed Architecture

### 1. Firmware settings storage

- Add a dedicated settings storage layer for device configuration.
- Store only device-side settings in firmware storage:
  - saved STA SSID
  - saved STA password
  - schema version and any future network-related flags
- Do not store controller layout in firmware.
- Use ESP32 `Preferences`/NVS as the first implementation target because it is the native runtime persistence path in the Arduino stack already used by this project.

### 2. Wi-Fi boot and fallback state machine

- On boot, load saved device settings.
- If no saved STA settings exist:
  - start AP mode immediately.
- If saved STA settings exist:
  - attempt STA connection.
  - do not keep AP active once STA is connected successfully.
  - if STA does not connect after bounded retries/backoff, start AP fallback mode.
- Add explicit internal states for:
  - no saved config
  - connecting
  - connected
  - fallback AP active
  - connection failed

### 3. Safe credential update flow

- Accept new Wi-Fi credentials from the UI as a candidate configuration.
- Attempt to connect using the candidate credentials without overwriting the stored working configuration first.
- If the candidate connection succeeds:
  - save the new credentials to NVS
  - switch the active network state to the new STA connection
  - disable AP broadcasting
- If the candidate connection fails:
  - keep the previously saved configuration untouched
  - report the failure to the UI
  - keep or re-enable AP so the user can retry

### 4. API changes

- Extend `GET /api/status` so the UI can render the new flow.
- Include:
  - whether saved Wi-Fi config exists
  - whether the device is attempting STA
  - whether AP fallback is active
  - the active STA SSID if available
  - whether a candidate update is in progress
- Keep password values out of all API responses.
- Update `POST /api/network/sta` so it:
  - validates input
  - starts a candidate connection attempt
  - only commits credentials after success
- Keep controller-layout persistence out of firmware APIs unless later requirements change.

### 5. Frontend flow

- Rework the main page so it shows:
  - the gamepad
  - one config button
- Add a same-page modal with:
  - close `X`
  - `Device Config` section
  - a visible separator
  - `Controller Config` section
- Device Config content:
  - SSID field
  - password field
  - connect action
  - clear status and error feedback
- Controller Config content:
  - layout dropdown
  - cookie-backed persistence on the browser device
  - default to the only currently supported layout

### 6. Cookie-backed controller layout

- Persist layout choice in browser cookies rather than on the ESP32.
- Load the cookie during page initialization and apply the selected layout.
- Keep the cookie schema small and versionable so future layouts can be added without changing firmware storage.

### 7. Security approach and tradeoffs

- Baseline protections:
  - never expose Wi-Fi passwords in status responses
  - never echo Wi-Fi passwords back into the UI
  - avoid serial logging of credential values
- Recommended first implementation:
  - store credentials in ESP32 NVS via `Preferences`
- Tradeoffs of this approach:
  - it is practical and fits the current Arduino-based firmware architecture
  - it survives reboot and normal firmware updates
  - it does not provide strong protection against a determined attacker with physical access to the flash contents
- Stronger protection option:
  - use ESP32 flash encryption and secure boot features
- Complications of stronger protection:
  - setup is more complex and board/provisioning specific
  - development and recovery workflows become stricter
  - key management and manufacturing/reset procedures need to be defined
  - it may require a deeper move into ESP-IDF provisioning and deployment practices than the current project uses

### 8. Test architecture for AP and STA paths

- Keep the current AP-based Pi automation as the base path for fallback-mode validation.
- Add a separate STA-focused test path that does not depend on the browser UI.
- Use a local ignored env file for test secrets, for example:
  - `tools/pi/local.env`
  - variables such as `TEST_STA_SSID` and `TEST_STA_PASS`
- Commit only an example template file with placeholder variable names.
- The STA test should:
  - start from AP fallback mode or another reachable control path
  - submit candidate STA credentials through a direct API or test helper
  - wait for the ESP32 to join the shared network
  - verify AP shutdown after successful STA connect
  - verify `/api/status` over the STA path
  - reboot and verify saved-credential reconnect
- Add a failed-update test that:
  - seeds or confirms known-good credentials
  - submits intentionally bad candidate credentials
  - verifies the old credentials remain the stored working set
  - verifies reconnect still works after reboot
- Treat `game.local` and STA-connect success as separate assertions so mDNS regressions are visible independently of Wi-Fi association.

## Implementation Steps

1. Add a firmware-side settings service wrapping `Preferences`.
2. Refactor `NetworkManager` to support:
   - loading stored credentials
   - candidate STA connection attempts
   - delayed commit on success
   - AP disable on successful STA
   - retry/backoff and AP fallback
3. Extend status reporting and network configuration APIs in the web server.
4. Rework the embedded UI into:
   - main gamepad surface
   - config launch button
   - modal with separated device/controller sections
5. Add cookie helpers for controller layout persistence in the frontend.
6. Add tests for:
   - validation
   - candidate credential commit rules
   - status serialization
   - cookie persistence logic where practical
7. Add local secret-loading support for STA test credentials using ignored environment files and documented variable names.
8. Extend Pi and hardware integration checks for:
   - boot with no credentials
   - successful save after verified STA connect
   - failed candidate credentials preserving prior saved settings
   - AP shutdown after successful STA connect
   - reboot and reconnect using saved credentials
   - status endpoint verification over both AP and STA paths where feasible
9. Update README and user documentation after behavior is implemented.

## Open Technical Recommendation

For this project, the pragmatic recommendation is:

- Start with `Preferences`/NVS plus strict secret-handling rules in firmware and API responses.
- Document clearly that this reduces casual exposure but does not fully protect against determined physical extraction from a lost device.
- If the threat model truly requires protection against offline flash dumping, plan a second phase for ESP32 flash encryption and secure boot rather than trying to improvise weak application-level encryption.
