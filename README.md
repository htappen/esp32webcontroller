# ESP32 Web Controller

_Use your phone as a controller on Windows, MacOS, Linux and Switch!_

Ever want to play a multiplayer game but you don't have enough controllers? No problem! 
Just grab an ESP32, flash it with this firmware, then connect your phones to it. Everyone's phone becomes a controller!

# Features
* Turns phones into controllers for Windows, Mac, Linux or Switch
* Supports up to 4 phone controllers on a single device
* Only extra hardware is a cheap and small ESP32 (preferably S3)
* Works over Bluetooth or USB so you can try it on all kinds of devices

# Getting started

## What you need
For best experience, you need:
* An ESP32 S3 board ( [example](https://www.aliexpress.us/item/3256807408682270.html) )
* Windows, MacOS, or Linux PC to set up the ESP32
* Some familiarity with flashing ESP32 devices

You can also use a ESP32-WROOM, but you'll limited to 1 controller and Windows/Mac/Linux over Bluetooth.

## Steps
First, you need to flash your ESP32 with the firmware. Instructions:
1. Clone the repo to any PC. Update the Git submodules
   - `git submodule update --init --recursive`
2. Setup local dev environment with PlatformIO and ESP32 toolchain
   - `./tools/setup_env.sh` 
3. (optional) Copy `local.env.example` to the same dir. Rename it to `local.env`. Replace the SSID and password
with your desired wifi network info.
4. Set environment variables to configure how you'll bridge your phones and game console. On Linux, `export ...=...`. On Windows, `sete ...=...`
   - `CONTROLLER_BOARD`: What type of ESP32 board you're using. `s3` or `wroom`
   - `CONTROLLER_DEVICE_UUID`: a UUID that decides your board's name
   - `CONTROLLER_HOST_MODE`: How you'll connect the ESP32 to your device. One of `usb_switch`, `usb_xinput`, `ble`
5. Hook your ESP32 to your PC. Put it in flash mode
6. Build and Flash the ESP32 using `./tools/upload_firmware.sh` 

Once you've flashed an ESP32, you're ready to play!
1. Plug the ESP32 into a USB port on your console of choice if you're using USB, or power the device and pair it from your console.
2. If you didn't already set up a wifi network for the ESP32, connect your phone to the network it broadcasts. It will be something like `<adjective> <noun> Pad`.
3. From the phone, navigate to `http://<adjective>-<noun>.local` (using the same adjective and noun from earlier)
4. Play!
5. Optionally, you can enter your wifi network and password in the settings menu so you can communicate with the ESP32 over that.

## Troubleshooting

- If the host does not see the controller, remove the old Bluetooth pairing for the current `<Adjective> <Noun> Pad`, power-cycle the ESP32, and pair again.
- If the phone says the page cannot be reached, make sure it is still connected to the current device AP and try the device's `.local` hostname again.
- If controls stop responding, refresh the page on the phone and reconnect the Bluetooth controller if needed.
- Keep only one phone connected to the controller page at a time for predictable behavior.

# Developer notes
Want to fork or add? Here's a bunch of info

## Connectivity Model

- Phone connectivity:
  - `AP mode`: ESP32 hosts its own Wi-Fi AP (derived from the build UUID).
  - `Shared Wi-Fi mode (STA)`: ESP32 joins an existing LAN SSID so phones on that LAN can access it.
  - `AP+STA mode`: keep AP active as fallback while joining shared Wi-Fi.
- Host connectivity:
  - BLE builds advertise as a BLE HID gamepad.
  - `usb_switch` builds enumerate as a wired USB controller for Switch-style hosts.
  - `usb_xinput` builds enumerate as a wired Xbox 360 class device using a custom TinyUSB class-driver backend modeled on `gp2040-ce`.
- Controller data path:
  - Browser sends controller packets via WebSocket to `ws://<device-hostname>.local:81` when the controller is opened by hostname.

## Layout

- `firmware/`: PlatformIO firmware and embedded web assets.
- `web/`: Optional frontend dev workspace (build output copied into `firmware/data/`).
- `docs/`: Architecture and protocol docs.
- `tools/`: Utility scripts for packing assets and monitoring firmware.
- `test/host/`: Host-side protocol and mapping tests.

## Remote Pi E2E

Use the Pi runner when the board is physically connected to the Raspberry Pi instead of the development machine.

- The first positional port for `./tools/pi/run_remote_e2e.sh` is the serial device path on the Pi, not the local workstation.
- The script stages the current tracked repo snapshot to the Pi, ensures the Pi-side repo environment exists, then builds, flashes, captures boot logs, and runs the Pi-side tests there.
- Example BLE run: `./tools/pi/run_remote_e2e.sh /dev/ttyACM0`
- Example USB XInput run: `CONTROLLER_HOST_MODE=usb_xinput ./tools/pi/run_remote_e2e.sh /dev/ttyACM0`
- Override the Pi target with `PI_HOST=controller-pi` or `REMOTE_BASE_DIR=/home/controller/controller-pi-e2e` as needed.

Current USB XInput note:

- The repo no longer uses Arduino's generic vendor helper for `usb_xinput`.
- `firmware/src/usb_xinput_gamepad.cpp` now registers a custom TinyUSB app driver through `usbd_app_driver_get_cb()` and handles descriptor open, endpoint transfer, and minimum XInput control behavior directly.
- This path builds successfully, but still needs real Linux host validation before it should be treated as stable.

## Device Names

- Wi-Fi network: `<Adjective> <Noun> Pad`
- Wi-Fi security: open network, no password
- Controller page: `http://<adjective>-<noun>.local`
- Bluetooth controller name: `<Adjective> <Noun> Pad`

Builds derive these names from a UUID using a curated short-word subset of the `python-petname` English lists. Test automation defaults to the committed test UUID `019cba78-45f9-7003-ad59-451b095628be`. The most recent build identity is persisted to `build/device_identity.env`.


## Connection APIs (Scaffold)

- `GET /api/status`:
  - Returns current network mode/AP/STA status, host transport status, and WebSocket controller status.
- `POST /api/network/sta`:
  - Body: `{ "ssid": "...", "pass": "..." }`
  - Stores STA credentials and starts shared Wi-Fi connection attempt.

## Submodules

This repository links upstream dependencies via git submodules:

- `third_party/virtual-gamepad-lib`
- `third_party/ESP32-BLE-Gamepad`

After cloning:

```bash
git submodule update --init --recursive
```

The embedded web UI uses the `virtual-gamepad-lib` submodule as a build-time dependency through the Vite app. The firmware image does not need a copied `firmware/data/vendor/` mirror of that package.
