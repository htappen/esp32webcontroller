# USB Host Transport Refactor Plan

## Goal

Add wired USB host-connected controller support without turning the firmware into a transport-specific maze of conditionals.

The web control surface should stay mostly shared across BLE and USB modes. The firmware-side host transport should be isolated behind a small interface so BLE and USB can evolve independently.

## Constraints

- `ESP32-S3` is the primary USB target because it has native USB device support.
- Classic `ESP32-WROOM-32D` does not have native USB device support, so wired USB host mode is not a first-class implementation target there.
- For Xbox 360 / `usb_xinput`, descriptor-only emulation through Arduino-ESP32's generic vendor helper is not a sufficient foundation. A `gp2040-ce` comparison showed that the working approach uses a real TinyUSB custom class driver that owns descriptor callbacks, endpoint opening, and transfer/control behavior directly.
- Raspberry Pi end-to-end testing should remain part of the workflow, but USB mode changes the physical topology:
  - the ESP32 board stays attached to the developer workstation over USB
  - the Pi still drives the controller over Wi-Fi/web APIs
  - the USB host side is observed from the developer workstation instead of the Pi

## Architectural Direction

### 1. Keep one canonical controller state

Continue using `ControllerState` as the shared in-memory model for browser-originated input.

Shared pieces that should remain transport-agnostic:

- WebSocket input parsing
- `StateStore`
- controller timeout-to-neutral behavior
- the web UI
- HTTP status/control APIs where the behavior is not transport-specific

### 2. Replace transport-specific output mapping with a generic report

The current output path is BLE-shaped too early because `InputMapper` emits `BleReport`.

Refactor the mapper to emit a generic gamepad-oriented report, for example:

- buttons
- hat/dpad
- left/right sticks
- triggers

This report should be transport-neutral and represent the controller state in one canonical host-output form.

Possible name:

- `HostInputReport`

### 3. Introduce a transport interface

Add a narrow interface for host transports so the main loop and web/status code can interact with one abstraction instead of branching on BLE vs USB everywhere.

Example shape:

```cpp
struct HostTransportStatus {
  const char* transport;   // "ble" or "usb"
  const char* variant;     // "default", "pc", "switch"
  bool ready;
  bool connected;
  bool pairing_enabled;
};

class HostTransport {
 public:
  virtual bool begin() = 0;
  virtual void loop() = 0;
  virtual bool send(const HostInputReport& report) = 0;
  virtual bool resetConnection() = 0;
  virtual HostTransportStatus status() const = 0;
  virtual ~HostTransport() = default;
};
```

### 4. Implement separate transport backends

Do not implement transport selection by scattering `if (usb)` and `if (ble)` checks through the codebase.

Instead, create separate implementations:

- `BleHostTransport`
- `UsbPcHostTransport`
- `UsbSwitchHostTransport`

For `UsbPcHostTransport` specifically:

- prefer a custom TinyUSB class-driver path over Arduino's generic `USB_INTERFACE_VENDOR` path
- own `tud_descriptor_*` callbacks for the XInput personality
- own interface parsing, endpoint opening, and interrupt transfer flow directly
- treat `gp2040-ce`'s XInput driver as the reference design for structure, not a drop-in copy

Current status:

- this repo now has an initial custom TinyUSB app-driver backend for `usb_xinput`
- it registers through `usbd_app_driver_get_cb()`
- it owns the XInput interface `open()` path, opens endpoints directly with TinyUSB, primes OUT transfers, and sends IN reports with `usbd_edpt_xfer()`
- it handles the minimum vendor control requests needed for initial Linux/XInput host acceptance attempts
- it is not yet validated end to end against a Linux host, so descriptor/control quirks may still need iteration after real host testing
- Pi-side flashing no longer requires a manual reset-button press after upload; the tooling now uses `esptool --after watchdog_reset` for `ESP32-S3`
- a diagnostic `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` mode now exists so `usb_xinput` can boot without calling `USB.begin()` and stay on the Espressif `USB-Serial/JTAG` path while the built-in JTAG debugger is attached
- the temporary serial/ROM breadcrumb instrumentation used during early narrowing has been removed; the active debug path is now Pi-side OpenOCD + `xtensa-esp32s3-elf-gdb` against the S3 built-in JTAG interface
- Pi environment bootstrap now installs debugger prerequisites (`openocd`, `gdb`) and validates the built-in JTAG board config so debugger attach can be part of the normal Pi workflow
- debugger attach on the Pi is now proven on the real board; the non-deferred `usb_xinput` image still drops off USB/JTAG as soon as execution resumes, while the deferred image stays attached long enough for repeatable post-boot inspection

Each transport owns:

- bring-up and teardown
- host-specific connection semantics
- transport-specific status details
- descriptor/report formatting quirks
- host reset/forget behavior

### 5. Keep one coordinator above the transport

Retain the role of `HostConnectionManager`, but refactor it into a coordinator that owns exactly one active `HostTransport`.

That keeps the rest of the firmware interacting with:

- one send path
- one status surface
- one connection lifecycle abstraction

This is the main defense against spaghetti.

## Firmware Boundaries

### Shared code

These pieces should stay shared:

- `StateStore`
- `WsBridge`
- the web app assets and controller UI
- neutral timeout/reset logic
- the generic controller-state-to-host-report mapper
- the common `/api/status` envelope

### Transport-specific code

These pieces should become transport-specific:

- BLE advertising/pairing logic
- BLE bond forgetting
- USB enumeration handling
- USB descriptor identity
- TinyUSB class-driver integration for XInput-class USB personalities
- Switch-vs-PC USB personality
- transport-specific readiness and connection checks

## Status and UI Plan

The UI should explicitly tell the user what host transport is active.

Add transport identity to `/api/status`, for example:

```json
{
  "host": {
    "transport": "ble",
    "variant": "default",
    "ready": true,
    "connected": true,
    "pairingEnabled": true
  }
}
```

Recommended variants:

- BLE: `transport=ble`, `variant=default`
- PC USB: `transport=usb`, `variant=pc`
- Switch USB: `transport=usb`, `variant=switch`

UI implications:

- BLE mode shows pair/forget controls
- USB mode hides BLE-only actions
- USB mode shows host enumeration state instead of pairing state
- status text should say `Bluetooth`, `USB-PC`, or `USB-Switch` explicitly

## Build and Board Strategy

Do not compile every transport into every board target by default.

Prefer distinct board/mode build targets such as:

- `wroom + ble`
- `s3 + ble`
- `s3 + usb_pc`
- `s3 + usb_switch`

This keeps:

- flash usage more predictable
- board capabilities explicit
- preprocessor use localized to transport selection and board support

Separate PlatformIO environments are preferable to broad compile-time branching throughout the codebase.

For `usb_xinput`, prefer a dedicated build/backend combination that can opt into lower-level TinyUSB ownership where needed, instead of trying to share the exact same Arduino USB helper path as simpler vendor or HID-style transports. That is now the implemented direction in this repo.

## Testing Strategy

The test scenarios should stay mostly the same even though the host-observation topology changes.

### Shared test scenario vocabulary

The following assertions should remain common across BLE and USB:

- neutral packet produces neutral host state
- button press produces expected host button event
- axis movement produces expected host axis event
- timeout-to-neutral works
- `/api/status` reports the expected transport identity

### Transport-specific host probes

Keep the scenario logic shared, but split the host observation layer into per-transport probes.

Examples:

- `ble_host_probe`
- `linux_usb_host_probe`
- later, if needed, `macos_usb_host_probe`

Each probe should expose the same operations:

- wait until ready
- assert connected
- capture input event
- clear or reset host-side state

### Physical topology

BLE path:

- Pi drives the web control path
- Pi also acts as the BLE host observer

USB path:

- Pi drives the web control path over Wi-Fi/network
- ESP32 remains attached over USB to the developer workstation
- the developer workstation acts as the USB host observer

This means the USB E2E test becomes a two-host flow, but the high-level scenario can stay shared if the host probe boundary is clean.

## Recommended Implementation Order

1. Introduce `HostInputReport` and refactor `InputMapper` to emit it.
2. Add the `HostTransport` interface and convert the existing BLE path into `BleHostTransport`.
3. Refactor `HostConnectionManager` into a single-transport coordinator.
4. Extend `/api/status` with explicit transport and variant fields.
5. Update the web UI to show transport mode and hide BLE-only controls in USB mode.
6. Add `UsbSwitchHostTransport` on `ESP32-S3`.
7. [DONE] For `UsbPcHostTransport` / `usb_xinput`, port the first `gp2040-ce`-style custom TinyUSB class-driver skeleton instead of continuing on descriptor-only tuning.
8. [IN PROGRESS] Reuse the upstream raw descriptor tables, report struct/layout, string-descriptor helper, and endpoint-open/control behavior where practical, but adapt them to this repo's transport layer and ESP32-S3 runtime.
9. [IN PROGRESS] Add the USB host-probe-based E2E runner while keeping the existing BLE E2E route intact; the runner exists, but the new custom driver still needs real host validation.
10. [DONE] Use temporary deferred-mode breadcrumbs only long enough to confirm that the app reaches startup far enough to justify switching from print debugging to JTAG debugging, then remove the temporary prints.
11. [IN PROGRESS] Switch the active workflow to Pi-side OpenOCD + GDB on the ESP32-S3 built-in JTAG path.

Current result:

- Pi bootstrap now prepares OpenOCD/GDB prerequisites
- the repo contains Pi-side debugger launch helpers and a startup breakpoint script
- clean non-deferred `usb_xinput` reflashing still succeeds with software reboot
- the practical blocker on the normal image is still timing: after reboot the board can fall from `303a:1001` into repeated USB descriptor failures quickly enough that OpenOCD must attach during that window
- the deferred image removes that instability and can be inspected after boot; a fresh GDB attach lands in the idle task (`esp_pm_impl_waiti` / `prvIdleTask`), which means the board is alive enough for breakpoint refinement rather than more USB-presence triage
- refined deferred-build stepping now proves the generic startup path is healthy on hardware: Arduino `app_main` reaches `loopTask`, then project `setup()`, then `Serial.begin`, `delay`, `g_state.reset()`, `NetworkManager::begin()`, `HostConnectionManager::begin()`, `WebServerBridge::begin()`, and the later setup-side `Serial.printf(...)` calls
- that shifts the remaining suspicion away from early generic startup and onto the non-deferred/native-USB transport path itself
- with a temporary 10-second pre-`USB.begin()` hold and a retrying OpenOCD attach path, the normal image can now be caught over built-in JTAG too, but only at a much lower-level boundary: the earliest stable stop is `PC=0x40000400`, and resuming from there immediately drops the board off the JTAG device again
- that means the non-deferred failure is now narrowed below the ordinary Arduino startup chain and likely sits in a lower-level reset/runtime handoff associated with native USB bring-up rather than in `setup()`-level application code

## Initial Recommendation

Start with `ESP32-S3` and `USB-Switch` mode only for the first broadly supported USB transport.

Reasons:

- it matches the current hardware capabilities
- it avoids inventing a fake USB path for classic ESP32 hardware
- it keeps the first USB transport backend narrow
- it allows the PC/macOS path to follow later as either:
  - a PC-oriented HID mode, or
  - a second USB transport variant if Switch emulation is not ideal for general desktop compatibility

`usb_xinput` is now a separate low-level implementation track with a custom TinyUSB class driver, not a small descriptor variant of the old Arduino vendor backend.
