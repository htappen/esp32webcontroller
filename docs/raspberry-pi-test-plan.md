# Raspberry Pi E2E Test Plan

## Goal

Replace manual phone-and-host validation with a repeatable end-to-end test that runs against:

- a flashed `ESP32-WROOM-32D` device under test
- a Raspberry Pi 4 acting as both:
  - the Wi-Fi client/browser-side input source
  - the BLE host receiving the ESP32 gamepad

The test should be runnable remotely from the ChromeOS development machine over SSH.

## Why Raspberry Pi

- A Pi can join the ESP32 access point over Wi-Fi and pair over Bluetooth on the same machine.
- The Pi can expose Linux input events locally for assertions.
- The Pi can be driven remotely over SSH, which fits the ChromeOS workflow.
- This avoids Crostini-specific uncertainty around Bluetooth and device passthrough.

## Recommended Test Architecture

### Control Plane

- ChromeOS machine runs the top-level orchestration script.
- The orchestration script SSHes into the Pi and starts the Pi-side test runner.
- All logs and artifacts are copied back over SSH/SCP.

### Data Plane

- Pi joins ESP32 AP `ESP32-Controller`.
- Pi opens the controller web UI at `http://game.local`.
- Pi pairs to BLE device `ESP32 Web Gamepad`.
- Pi injects UI input and records Linux input events from the BLE gamepad device.

## Implementation Phases

### Phase 1: Pi Host Baseline

Add Pi-side utilities to prove the host path works without browser automation.

Deliverables:

- `tools/pi/check_bluetooth.sh`
- `tools/pi/check_wifi_ap.sh`
- `tools/pi/pair_ble_gamepad.sh`
- `tools/pi/capture_input_events.py`

Checks:

- Pi can scan for and pair to `ESP32 Web Gamepad`
- BLE gamepad appears as a Linux input device
- Pi can join `ESP32-Controller`

### Phase 2: Scripted Direct-WebSocket E2E

Automate the full data path except for the browser UI.

Deliverables:

- `tools/pi/send_controller_packet.py`
- `tools/pi/e2e_ws_to_ble_test.sh`

Flow:

1. Join ESP32 AP.
2. Pair to the BLE gamepad.
3. Confirm `http://192.168.4.1/api/status` and `http://game.local/api/status` return equivalent controller status.
4. Start input capture on the Pi.
5. Send known controller packets to `ws://game.local:81`.
6. Assert corresponding Linux input events arrive.

Pass criteria:

- Neutral packet causes no pressed buttons.
- Test button packet produces the expected button event.
- Test axis packet produces the expected axis movement.
- Disconnect/timeout returns inputs to neutral.

### Phase 3: Browser-Driven Full E2E

Add browser automation so the test covers the served web UI as well.

Deliverables:

- `tools/pi/browser_ui_test.py`
- `tools/pi/e2e_browser_test.sh`

Flow:

1. Recreate a repo-managed Python venv on the Pi for all Pi-side Python helpers and install the Python test requirements there.
2. Start headless Chromium on the Pi from that venv-backed harness.
3. Open `http://game.local`.
4. Drive the on-screen controller with browser automation against the actual SVG tap targets.
5. Assert matching Linux input events from the BLE device.

Pass criteria:

- Page loads successfully from the ESP32.
- WebSocket connection becomes active.
- Clicking the on-screen A button produces a WebSocket payload with `btn.a = 1`.
- The same on-screen A button click produces the expected BLE host button event.

## Repo Changes Needed

### New Scripts

- `tools/create_pi_ssh_key.sh`
- `tools/pi/bootstrap_pi.sh`
- `tools/pi/run_remote_e2e.sh`
- `tools/pi/check_bluetooth.sh`
- `tools/pi/check_wifi_ap.sh`
- `tools/pi/pair_ble_gamepad.sh`
- `tools/pi/e2e_ws_to_ble_test.sh`
- `tools/pi/e2e_browser_test.sh`
- `tools/pi/browser_ui_test.py`

### New Test Area

- `test/pi/`
- `test/pi/fixtures/`
- `test/pi/playwright/`

### New Documentation

- Pi setup guide
- SSH coordination guide
- Troubleshooting notes for BLE pairing and input capture

## Shared Settings Between ChromeOS And Pi

These values must stay in sync:

- Pi SSH hostname or IP
- Pi SSH username
- SSH private key path on ChromeOS
- matching SSH public key in `/home/<pi-user>/.ssh/authorized_keys` on the Pi
- optional fixed Pi hostname alias such as `controller-pi`

Recommended defaults:

- Pi username: `controller`
- Pi hostname: `controller-pi`
- SSH key path on ChromeOS: `~/.ssh/controller_pi_ed25519`

Avoid relying on a shared password for automation. Use SSH keys instead.

## Open Technical Questions

- Which Linux event interface is most stable for assertions on Pi OS: `evdev`, `js`, or both?
- Does the BLE gamepad reconnect reliably after repeated test cycles?
- Does headless Chromium suffice, or is `Xvfb` required for touch-style Playwright actions?
- Is Pi onboard Bluetooth stable enough, or should the testbed standardize on a USB dongle?

## Recommended First Implementation

Start with Phase 2 first.

Reason:

- It covers the most important firmware path quickly.
- It avoids Playwright and display-stack complexity.
- It provides a reliable baseline before UI automation is added.

After Phase 2 is stable, add Phase 3 on top.
