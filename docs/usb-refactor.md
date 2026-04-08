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
- a diagnostic `CONTROLLER_USB_XINPUT_DEFER_BEGIN=1` mode now exists so `usb_xinput` can boot without calling `USB.begin()` and stay on the Espressif `USB-Serial/JTAG` serial path while debug setup is prepared
- the temporary serial/ROM breadcrumb instrumentation used during early narrowing has been removed; the active debug path is now Pi-side OpenOCD + `xtensa-esp32s3-elf-gdb` over Raspberry Pi GPIO-JTAG rather than the ESP32-S3 built-in USB JTAG interface
- Pi environment bootstrap now installs debugger prerequisites (`openocd`, `gdb`) and validates the Raspberry Pi GPIO-JTAG board config so debugger attach can be part of the normal Pi workflow
- debugger attach on the Pi is now proven on the real board; USB-path debugging now assumes Pi `GPIO3` low at reset time and uses the GPIO-JTAG route instead of relying on built-in USB JTAG
- enumeration and Linux host binding now work on the Pi for the normal `usb_xinput` image:
  - `lsusb` shows `045e:028e`
  - Linux binds `xpad`
  - the device appears as `Microsoft X-Box 360 pad` with `/dev/input/event4` and `/dev/input/js0`
- the remaining blocker has moved past enumeration:
  - WebSocket packets reach the firmware and the `wsPacketsReceived` / `wsPacketsApplied` counters advance
  - but the Pi-side USB E2E flow still sees no runtime input events from `xpad` for button and axis packets
  - the active bug is now "reports appear to be accepted by firmware but are not surfacing as host-visible Xbox input events"
- the latest rerun still reproduces that exact boundary on hardware:
  - neutral packet assertions pass
  - `A=1` still fails with no `BTN_SOUTH` event on `/dev/input/event4`
  - so the host-visible runtime report path is still the decisive bug, not device discovery or WebSocket ingress
- the flash workflow has now been adjusted for that debug loop:
  - `tools/upload_firmware.sh` supports `--skip-uploadfs`
  - `tools/pi/wait_for_acm_then_upload.sh` now defaults to skipping `uploadfs` so the first ACM appearance can be used for a single immediate firmware upload rather than a two-open `uploadfs` + `upload` sequence
  - the repo now also has a prebuilt direct-flash route for the short ACM window: `tools/write_prebuilt_firmware.sh` and `tools/pi/wait_for_acm_then_write_prebuilt_firmware.sh`

### Current Comparison Findings

The current `usb_switch` path and `usb_xinput` path are useful contrasts because they fail at very different layers.

`usb_switch` today:

- uses Arduino's `USBHID` stack rather than a custom TinyUSB class driver
- has one compact HID report descriptor and one report struct
- converts the neutral `HostInputReport` directly into a report and sends it through `USBHID::SendReport()`
- relies on standard HID host behavior instead of vendor control/auth semantics

`usb_xinput` today:

- owns a raw Xbox 360 device descriptor and a multi-interface configuration descriptor
- owns TinyUSB descriptor callbacks, class-driver registration, endpoint opening, vendor control handling, and interrupt transfers
- tracks endpoint state manually in `XInputDriverState`
- queues reports manually with `usbd_edpt_xfer()`

That comparison narrows likely fault classes.

The current `usb_xinput` implementation is no longer failing at:

- device descriptor acceptance
- configuration descriptor acceptance
- Linux `xpad` binding
- basic host recognition as an Xbox 360-class device

The remaining likely fault classes are:

1. Runtime report format mismatch.
   - The 20-byte `XInputControlReport` may still differ from what the Linux `xpad` path expects on the interrupt IN endpoint, even if enumeration succeeds.

2. Interrupt transfer scheduling or readiness mismatch.
   - `send()` only queues through `xinputStartReportTransfer()` when `interfaces_opened`, `tud_ready()`, and `usbd_edpt_ready()` all line up. A state or timing issue here could make reports appear accepted at the firmware layer but never reach the host.

3. Missing or incomplete handling of host OUT-side initialization.
   - Linux logs `unable to receive magic message: -32`, which is a strong sign that some expected OUT/control exchange is still not handled the way `xpad` expects after bind.

4. Endpoint semantics mismatch versus the upstream reference.
   - The current endpoint-open and transfer logic is self-contained, but not yet proven to be endpoint-for-endpoint equivalent to a known-good `gp2040-ce` XInput implementation.

### Active Debug Plan

The debugging work should now focus on runtime report delivery, not on raw enumeration.

#### Phase 1: Tighten the runtime comparison

1. Compare the current `usb_xinput` runtime path against the `gp2040-ce` reference specifically at:
   - report struct layout
   - interrupt IN transfer size and cadence
   - host OUT / rumble / init packet handling
   - any state gating before the first IN report is allowed

2. Compare the current `usb_xinput` send path against the simpler `usb_switch` path to keep the firmware-side questions concrete:
   - when does `send()` return true
   - what conditions suppress a transfer
   - what state indicates the host is truly ready for runtime input

3. Keep the Pi E2E runner as the truth source for regressions:
   - USB enumeration and `xpad` bind must still pass
   - WebSocket debug counters must still advance
   - the next pass criterion is real `event4` / `js0` input, not only status counters
   - the current known-failing assertion remains `BTN_SOUTH` for the `A=1` packet, which makes it the fastest regression check after each reflash

#### Phase 2: Instrument the runtime delivery edge

Add targeted temporary instrumentation only around the decisive runtime points:

1. In `UsbXInputGamepadBridge::send()`:
   - log whether `started_`, `interfaces_opened`, `tud_ready()`, and `usbd_edpt_ready()` are true
   - log when `report_dirty` is set and when `xinputStartReportTransfer()` returns false

2. In `xinputStartReportTransfer()`:
   - log endpoint address, packet length, and whether `usbd_edpt_xfer()` succeeds

3. In `xinputDriverXfer()`:
   - log IN transfer completions, failures, and requeue behavior
   - log OUT transfers with endpoint address and length so the host-side initialization sequence becomes visible

The goal is to answer one narrow question:

- are we failing to queue runtime IN reports at all, or are we queueing them and the host is discarding them?

#### Phase 3: Validate host-init behavior

Use the Pi host logs together with firmware instrumentation to map the first few seconds after bind:

1. Capture fresh `dmesg` around the first post-bind packet send.
2. Correlate that with firmware-side OUT/control logs.
3. Verify whether Linux sends the same initialization or "magic message" pattern every run.
4. Implement only the minimum additional OUT/control behavior needed to clear that host-init mismatch before broadening the driver.

#### Phase 4: Optional interactive GPIO-JTAG debugging

If print-style instrumentation still leaves ambiguity, switch to the already-proven Pi GPIO-JTAG path.

Use interactive GPIO-JTAG when we need to inspect:

- `g_driver_state.report_in_flight`
- `g_driver_state.report_dirty`
- endpoint addresses in `g_driver_state`
- whether `xinputDriverXfer()` is reached for the control IN endpoint after a packet send
- whether the send path is blocked in `usbd_edpt_ready()` or failing inside `usbd_edpt_xfer()`

Recommended interactive JTAG flow:

1. Flash the normal `usb_xinput` image first with no debugger attached.
2. Only if runtime report delivery still fails, prepare the Pi GPIO-JTAG strap path.
3. Attach OpenOCD + `xtensa-esp32s3-elf-gdb` over the Raspberry Pi GPIO wiring.
4. Break on:
   - `UsbXInputGamepadBridge::send`
   - `xinputStartReportTransfer`
   - `xinputDriverXfer`
5. Inspect whether a packet send results in:
   - a queued IN transfer
   - a completed IN transfer callback
   - a requeue or failure path

This is the highest-signal interactive option because the board now survives normal `usb_xinput` startup and binds on the host; the ambiguity is at runtime transfer behavior, not early boot.

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
   - Enumeration and `xpad` binding now work, so the next comparison focus is runtime interrupt-report behavior and host OUT/init handling rather than raw descriptor acceptance.
9. [IN PROGRESS] Add the USB host-probe-based E2E runner while keeping the existing BLE E2E route intact.
   - The Pi-side USB runner now verifies:
     - `045e:028e` enumeration
     - `xpad` binding
     - `event4` / `js0` visibility
     - WebSocket packet counters advancing
   - It does not pass end to end yet because runtime Xbox input events are still missing from the Linux host path.
10. [DONE] Use temporary deferred-mode breadcrumbs only long enough to confirm that the app reaches startup far enough to justify switching from print debugging to JTAG debugging, then remove the temporary prints.
11. [NEXT] Instrument and debug the runtime XInput report-delivery path.
12. [OPTIONAL] Use interactive Raspberry Pi GPIO-JTAG debugging if transfer instrumentation does not isolate the runtime failure cleanly enough.
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
