# Raspberry Pi 4 Setup For Automated ESP32 Testing

## Purpose

This guide prepares a Raspberry Pi 4 to act as the automated flasher, host observer, and browser/input runner for ESP32 end-to-end tests.

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
