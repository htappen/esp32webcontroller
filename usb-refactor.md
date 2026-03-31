# USB Host Transport Refactor Plan

## Goal

Add wired USB host-connected controller support without turning the firmware into a transport-specific maze of conditionals.

The web control surface should stay mostly shared across BLE and USB modes. The firmware-side host transport should be isolated behind a small interface so BLE and USB can evolve independently.

## Constraints

- `ESP32-S3` is the primary USB target because it has native USB device support.
- Classic `ESP32-WROOM-32D` does not have native USB device support, so wired USB host mode is not a first-class implementation target there.
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
7. Add the USB host-probe-based E2E runner while keeping the existing BLE E2E route intact.

## Initial Recommendation

Start with `ESP32-S3` and `USB-Switch` mode only.

Reasons:

- it matches the current hardware capabilities
- it avoids inventing a fake USB path for classic ESP32 hardware
- it keeps the first USB transport backend narrow
- it allows the PC/macOS path to follow later as either:
  - a PC-oriented HID mode, or
  - a second USB transport variant if Switch emulation is not ideal for general desktop compatibility
