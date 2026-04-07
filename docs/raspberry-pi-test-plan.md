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
- For `usb_xinput`, the Pi can also act as the Linux USB host observer once the ESP32-S3 OTG/device path is physically connected and the custom TinyUSB XInput driver is flashed.

## Recommended Test Architecture

### Control Plane

- ChromeOS machine runs the top-level orchestration script.
- The orchestration script SSHes into the Pi and starts the Pi-side test runner.
- All logs and artifacts are copied back over SSH/SCP.

### Data Plane

- Pi joins the ESP32 AP using the UUID-derived SSID, for example `Sunny Maple Pad`.
- Pi opens the controller web UI at the UUID-derived hostname, for example `http://sunny-maple.local`.
- Pi pairs to the BLE device using the same UUID-derived name, for example `Sunny Maple Pad`.
- Pi injects UI input and records Linux input events from the BLE gamepad device.

For wired USB validation on `ESP32-S3`:

- Pi still drives the controller web path over Wi-Fi.
- Pi also observes Linux USB/XInput enumeration and input events.
- The flashed `usb_xinput` firmware now uses a custom TinyUSB app driver via `usbd_app_driver_get_cb()` instead of Arduino's generic vendor helper, so validation should focus on the custom driver and physical USB path.
- The default Pi bring-up flow should first try a plain flash/upload/startup cycle with no GPIO-JTAG prep. Only after that fails should it force Pi GPIO3/GPIO4 low and enter the GPIO-JTAG recovery/debug path.

## Implementation Phases

### Phase 1: Pi Host Baseline

Add Pi-side utilities to prove the host path works without browser automation.

Deliverables:

- `tools/pi/check_bluetooth.sh`
- `tools/pi/check_wifi_ap.sh`
- `tools/pi/pair_ble_gamepad.sh`
- `tools/pi/capture_input_events.py`

Checks:

- Pi can scan for and pair to the UUID-derived BLE name
- BLE gamepad appears as a Linux input device
- Pi can join the UUID-derived AP SSID

### Phase 2: Scripted Direct-WebSocket E2E

Automate the full data path except for the browser UI.

Deliverables:

- `tools/pi/send_controller_packet.py`
- `tools/pi/e2e_ws_to_ble_test.sh`
- `tools/pi/e2e_ws_to_usb_test.sh`

Flow:

1. Join ESP32 AP.
2. Pair to the BLE gamepad.
3. Confirm `http://192.168.4.1/api/status` and the UUID-derived `.local` hostname return equivalent controller status.
4. Start input capture on the Pi.
5. Send known controller packets to `ws://<device-hostname>.local:81`.
6. Assert corresponding Linux input events arrive.

Pass criteria:

- Neutral packet causes no pressed buttons.
- Test button packet produces the expected button event.
- Test axis packet produces the expected axis movement.
- Disconnect/timeout returns inputs to neutral.
- `/api/status` reports the expected host transport and variant.

Additional USB-PC pass criteria:

- Linux enumerates the flashed ESP32-S3 as `045e:028e`.
- The host reaches `SET_CONFIGURATION` successfully.
- The custom TinyUSB XInput driver accepts the minimum control sequence and produces an input-visible Xbox 360 class device.

### Phase 3: Browser-Driven Full E2E

Add browser automation so the test covers the served web UI as well.

Deliverables:

- `tools/pi/browser_ui_test.py`
- `tools/pi/e2e_browser_test.sh`

Flow:

1. Recreate a repo-managed Python venv on the Pi for all Pi-side Python helpers and install the Python test requirements there.
2. Start headless Chromium on the Pi from that venv-backed harness.
3. Open the UUID-derived `.local` hostname served by the flashed firmware.
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
- Does the current custom TinyUSB XInput driver need more `gp2040-ce`-style control/auth behavior before Linux consistently accepts it?

## Recommended First Implementation

Start with Phase 2 first.

Reason:

- It covers the most important firmware path quickly.
- It avoids Playwright and display-stack complexity.
- It provides a reliable baseline before UI automation is added.

After Phase 2 is stable, add Phase 3 on top.
