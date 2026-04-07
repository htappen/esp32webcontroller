# Raspberry Pi 4 Setup For Automated ESP32 Testing

## Purpose

This guide prepares a Raspberry Pi 4 to act as the automated flasher, host observer, and browser/input runner for ESP32 end-to-end tests.

That now includes both:

- BLE host observation for classic Bluetooth gamepad tests
- USB/XInput host observation for `ESP32-S3` `usb_xinput` builds that use the custom TinyUSB class-driver backend

## Recommended OS

Use `Raspberry Pi OS with desktop (64-bit)` if you plan to run Chromium or Playwright against the real controller UI.

Use `Raspberry Pi OS Lite (64-bit)` only if you intend to stop at direct WebSocket injection and do not need browser-driven UI tests yet.

For the full route planned in this repository, the desktop image is the safer default.

## Hardware Assumptions

- Raspberry Pi 4
- microSD card with Raspberry Pi OS
- Ethernet connection for SSH/control from ChromeOS
- onboard Wi-Fi enabled
- onboard Bluetooth enabled
- ESP32 controller board connected to the Pi over USB for flashing and boot-log capture
- for `usb_xinput` validation, the ESP32-S3 OTG/device USB path must also be connected to the Pi host path so Linux sees the flashed board as a USB device, not just as a serial/flashing target

## Naming And Access Conventions

Keep these values consistent between ChromeOS and the Pi:

- Pi hostname: `controller-pi`
- Pi username: `controller`
- SSH private key on ChromeOS: `~/.ssh/controller_pi_ed25519`
- SSH public key installed on Pi: `/home/controller/.ssh/authorized_keys`

You may change these names, but then update all scripts and local shell examples to match.

## Step 1: Flash The Pi OS Image

In Raspberry Pi Imager:

1. Choose the Raspberry Pi OS image.
2. Open the advanced settings before writing the image.
3. Set:
   - hostname: `controller-pi`
   - username: `controller`
   - password: choose a temporary local setup password
   - enable SSH
   - configure Wi-Fi only if you also want the Pi on your normal LAN over Wi-Fi
4. Write the image to the microSD card.

If Ethernet is available, prefer Ethernet as the stable management link and reserve Wi-Fi for joining the ESP32 AP during tests.

## Step 2: Generate SSH Credentials On ChromeOS

From the ChromeOS/Linux development environment:

```bash
./tools/create_pi_ssh_key.sh
```

Default output:

- private key: `~/.ssh/controller_pi_ed25519`
- public key: `~/.ssh/controller_pi_ed25519.pub`
- SSH config entry in `~/.ssh/config` for host `controller-pi`

If you want a different path:

```bash
./tools/create_pi_ssh_key.sh ~/.ssh/my_custom_pi_key
```

## Step 3: Install The SSH Public Key On The Pi

Temporarily use the password you configured in Raspberry Pi Imager.

From ChromeOS:

```bash
ssh-copy-id -i ~/.ssh/controller_pi_ed25519.pub controller@controller-pi
```

If name resolution is not working yet, replace `controller-pi` with the Pi's LAN IP address.

Then verify key-based access:

```bash
ssh -i ~/.ssh/controller_pi_ed25519 controller@controller-pi
```

After SSH keys work, disable password-based SSH login if you want the test box locked down further.

## Step 4: Update The Pi

SSH into the Pi and run:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Reconnect over SSH after reboot.

## Step 5: Install Test Dependencies On The Pi

Run on the Pi:

```bash
sudo apt install -y \
  bluetooth bluez bluez-tools \
  chromium \
  python3 python3-pip python3-venv \
  python3-evdev python3-serial \
  jq tmux git
```

If the browser route needs a virtual display in headless SSH sessions, also install:

```bash
sudo apt install -y xvfb
```

The checked-in Pi test harness uses a repo-managed Python venv on the Pi instead of global `pip` installs. The test wrappers recreate that venv automatically through `tools/pi/setup_python_harness.sh`.

That venv is created with `--system-site-packages` so the repo-managed environment can still use apt-provided BlueZ bindings such as `dbus` and `gi` while keeping the repo's Python entrypoints inside one venv.

## Step 6: Enable Required Services

Run on the Pi:

```bash
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
```

Check Bluetooth is available:

```bash
bluetoothctl show
```

## Step 7: Clone The Repository On The Pi

Run on the Pi:

```bash
git clone <repo-url> ~/controller
cd ~/controller
git submodule update --init --recursive
./tools/setup_env.sh
```

The Pi and ChromeOS machine should use the same repository branch when debugging cross-machine test failures.

The top-level `./tools/pi/run_remote_e2e.sh` script stages the current tracked repo snapshot from ChromeOS to the Pi before a test run, so the Pi does not need a perfectly up-to-date manual clone for every firmware change. It still needs the one-time dependency setup from `./tools/setup_env.sh`.

## Step 8: Verify ChromeOS To Pi SSH Settings

These settings must align:

- ChromeOS shell commands use `controller@controller-pi`
- ChromeOS scripts point to `~/.ssh/controller_pi_ed25519`
- Pi actually has username `controller`
- Pi hostname resolves as `controller-pi`, or ChromeOS uses the Pi IP consistently

Recommended optional SSH config on ChromeOS:
This is now added automatically by `tools/create_pi_ssh_key.sh` and updated in place on reruns.

```sshconfig
Host controller-pi
  HostName controller-pi
  User controller
  IdentityFile ~/.ssh/controller_pi_ed25519
```

Do not store this repository’s automation around a password prompt. Use SSH keys.

## Step 9: Verify The Pi Test Capabilities

Run on the Pi:

```bash
bluetoothctl list
ip link
chromium --version
python3 -c "import evdev, serial; print('python deps ok')"
```

Expected outcome:

- Bluetooth adapter present
- Wi-Fi interface present
- Chromium installed
- Python BLE/input helpers import cleanly

## Step 10: Test Access To The ESP32

Once the ESP32 is powered:

1. On the Pi, join the ESP32 Wi-Fi network, for example `Sunny Maple Pad`.
2. Confirm the UUID-derived `.local` hostname, for example `http://sunny-maple.local`, opens in Chromium or via `curl`.
3. Use `bluetoothctl scan on` and look for the matching BLE name, for example `Sunny Maple Pad`.

This confirms the Pi can act as both test browser host and BLE receiver.

If the ESP32 is connected to the Pi over USB, the same box can now also build and flash it during `./tools/pi/run_remote_e2e.sh`.

For `usb_xinput` validation, also confirm:

1. The ESP32-S3 is reset into normal firmware mode, not ROM download mode.
2. `lsusb` shows the expected gamepad VID/PID when the `usb_xinput` firmware is flashed, rather than only `303a:1001`.
3. The Pi-side USB path is connected to the ESP32-S3 OTG/device port, not only to a serial/JTAG connector.

## Step 11: Wire Raspberry Pi GPIO JTAG For ESP32-S3

The Pi-side debugger flow now uses Raspberry Pi GPIO bitbang JTAG instead of the ESP32-S3 built-in USB JTAG path.

Use this wiring:

- ESP32-S3 `GPIO39` `MTCK` -> Raspberry Pi `GPIO11` (physical pin 23)
- ESP32-S3 `GPIO40` `MTDO` -> Raspberry Pi `GPIO24` (physical pin 18)
- ESP32-S3 `GPIO41` `MTDI` -> Raspberry Pi `GPIO25` (physical pin 22)
- ESP32-S3 `GPIO42` `MTMS` -> Raspberry Pi `GPIO7` (physical pin 26)
- ESP32-S3 `GND` -> Raspberry Pi `GND`
- ESP32-S3 `3V3` -> Raspberry Pi `3.3V` only if you intentionally power the board from the Pi

The repo OpenOCD config for this path is:

```bash
tools/pi/esp32s3_rpi_gpio_jtag.cfg
```

Useful commands on the Pi:

```bash
cd ~/controller-pi-e2e
./tools/pi/flash_or_debug_s3.sh
./tools/pi/prepare_s3_gpio_jtag.sh
./tools/pi/reset_s3_watchdog_if_present.sh
./tools/pi/start_openocd_s3_gpio_jtag.sh
./tools/pi/debug_attach_noreset_s3.sh
./tools/pi/stop_openocd_s3_gpio_jtag.sh
```

Use `./tools/pi/flash_or_debug_s3.sh` as the default S3 procedure. It first runs a normal build/erase/upload/startup check with no GPIO-JTAG preparation and does not force Pi GPIO3/GPIO4 low. Only if that plain path fails does it retry the S3 watchdog reset, attempt a fallback reflash, and then enter the GPIO-JTAG debugger flow.

The proved working attach path uses:

- Pi `GPIO3` low before board reset
- Pi `GPIO4` low before board reset
- best-effort serial watchdog reset on `/dev/ttyACM0` or `/dev/ttyACM1` if the ROM USB ACM port is currently visible
- single-core `cpu0` OpenOCD attach via `ESP32_S3_ONLYCPU 1`
- `target extended-remote :3333` in GDB

To force the Pi to drive GPIO3 low directly:

```bash
pinctrl set 3 op dl
pinctrl get 3
```

To force the Pi to drive GPIO4 low directly:

```bash
pinctrl set 4 op dl
pinctrl get 4
```

To check the Pi-side state of GPIO3 when validating the ESP32-S3 JTAG strap condition:

```bash
pinctrl get 3
```

To try the software reset path before a live attach when the board briefly shows up as `ttyACM0`/`ttyACM1`:

```bash
./tools/pi/reset_s3_watchdog_if_present.sh
```

This uses the existing `esptool --after watchdog_reset` path on the first stable ACM port it sees, then falls back cleanly if no serial port is present long enough.

## Operational Recommendations

- Use Ethernet for SSH management whenever possible.
- Let Wi-Fi switch to the ESP32 AP only for the duration of the test.
- Keep the Pi powered from a stable supply, not from a weak USB port.
- If Bluetooth reliability is poor, test a supported USB Bluetooth adapter before changing firmware behavior.

## Troubleshooting

### SSH Hostname Does Not Resolve

Use the Pi’s IP address instead of `controller-pi`, then fix mDNS or local DNS later.

### Key-Based SSH Does Not Work

- Confirm the public key is in `/home/controller/.ssh/authorized_keys`
- Confirm file permissions are correct:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Chromium Fails In SSH Sessions

Install and use `xvfb`, or switch to the direct WebSocket E2E path first.

### Bluetooth Device Does Not Appear

- Confirm the ESP32 is powered and advertising
- Run `bluetoothctl scan le`
- Remove stale pairings on the Pi and retry

### Wi-Fi Test Interrupts SSH

Use Ethernet for management. Do not depend on the same Wi-Fi interface for both the LAN control plane and the ESP32 AP during automated test runs.

### USB XInput Enumerates As `303a:1001`

- The ESP32-S3 is likely in ROM download mode or connected over the wrong USB path.
- Recheck the OTG/device USB connection used for the flashed firmware runtime.
- Reboot the board into normal firmware mode before interpreting any `usb_xinput` host-test result.

### Raspberry Pi GPIO JTAG Does Not Attach

- Confirm the ESP32-S3 JTAG wiring matches `tools/pi/esp32s3_rpi_gpio_jtag.cfg`.
- Confirm the Pi and ESP32-S3 share ground.
- Force Pi GPIO3 and GPIO4 low before reset if your board setup depends on strap-controlled external JTAG:

```bash
pinctrl set 3 op dl
pinctrl get 3
pinctrl set 4 op dl
pinctrl get 4
```

- If you enabled external JTAG through `STRAP_JTAG_SEL`, check Pi GPIO3 state during reset:

```bash
pinctrl get 3
```

- Start with the repo helper rather than the built-in USB JTAG config:

```bash
./tools/pi/flash_or_debug_s3.sh
```

- If the board is stuck in ROM flash/download mode but still briefly enumerates as `303a:1001` with `/dev/ttyACM0`, prefer the watchdog reset helper before pressing reset manually.
