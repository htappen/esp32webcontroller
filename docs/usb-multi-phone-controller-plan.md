# USB Multi-Phone Multi-Controller Implementation Plan

## Goal

While running on `CONTROLLER_BOARD=s3` in USB host modes:

- `CONTROLLER_HOST_MODE=usb_xinput`
- `CONTROLLER_HOST_MODE=usb_switch`

allow multiple phones to connect to the same ESP32 over WebSocket at the same time, assign each phone to a stable virtual controller slot, and expose each slot to the USB host as a separate controller.

The feature also needs:

- connection tracking per phone
- deterministic slot assignment and reuse
- disconnect and idle timeout removal
- UI feedback showing each phone whether it is connected and what controller number it owns

Resolved requirements:

- one composite USB device with multiple controllers is acceptable; no literal USB hub emulation needed
- v1 target is 4 controllers
- brief reconnects should reclaim the previous slot during a firmware-configurable grace period
- slot removal should be driven by WebSocket disconnect or existing WebSocket timeout
- the badge should show only the local phone's assigned number
- XInput is the first validation target; Switch can follow after the XInput path is proven

## Current State

Current code is single-controller end to end.

- Firmware stores one canonical controller state in [`firmware/src/state_store.h`](/home/htappen/controller/firmware/src/state_store.h).
- WebSocket handling tracks one boolean client presence in [`firmware/src/web_server.h`](/home/htappen/controller/firmware/src/web_server.h) and resets the single state on any disconnect/timeout in [`firmware/src/web_server.cpp`](/home/htappen/controller/firmware/src/web_server.cpp).
- Host transport exposes one `send(report)` entrypoint in [`firmware/src/host_transport.h`](/home/htappen/controller/firmware/src/host_transport.h).
- USB XInput implementation currently exposes one controller function with one report pipeline in [`firmware/src/usb_xinput_gamepad.cpp`](/home/htappen/controller/firmware/src/usb_xinput_gamepad.cpp).
- USB Switch implementation currently exposes one HID gamepad instance in [`firmware/src/usb_switch_gamepad.cpp`](/home/htappen/controller/firmware/src/usb_switch_gamepad.cpp).
- Browser UI assumes one connection and only shows generic browser-link state in [`web/src/page_state_controller.js`](/home/htappen/controller/web/src/page_state_controller.js).

## USB Device Shape

Implementation target is a **single composite USB device exposing multiple controllers**.

- no literal USB hub emulation required
- slot count target for v1 is 4
- XInput path is the first delivery target
- Switch support should be built after the XInput design is working end to end

## Proposed Architecture

### 1. Session and slot manager

Add a new firmware-side manager, likely something like `controller_session_manager.*`, responsible for:

- fixed maximum controller slot count of 4
- one slot per active phone
- mapping `ws client id -> slot id`
- tracking:
  - websocket client number
  - controller slot number
  - latest controller state
  - last packet timestamp
  - connected/disconnected state
  - optional browser-provided client identity token
- reclaiming slots on disconnect
- reclaiming slots on idle timeout
- generating neutral state when a slot is removed

This replaces the current single `StateStore` as the source of truth for USB modes.

### 2. Per-slot controller state

Introduce a multi-slot state store.

Options:

- keep `StateStore` as a per-slot primitive and wrap it in `MultiControllerStateStore`
- or replace it with a session-aware store directly

Needed behavior:

- independent monotonic `seq` validation per client/slot
- no cross-client state merge
- per-slot `last_update_ms`
- snapshot APIs for:
  - one slot
  - all active slots
  - connection summary for `/api/status`

### 3. Browser identity and handshake

Relying only on raw WebSocket client number is fragile across reconnects. Add an explicit browser identity handshake.

Suggested first packet or WS-side registration payload:

```json
{
  "type": "hello",
  "clientId": "<stable-browser-generated-uuid>",
  "clientName": "<optional>",
  "protocolVersion": 2
}
```

Then control packets can remain state packets, or can include the `clientId` only until the socket is bound.

Browser changes:

- generate and persist `clientId` in browser storage
- reconnect with same `clientId`
- receive slot assignment from firmware
- show assigned controller number in UI

Firmware changes:

- do not allocate a slot permanently until handshake completes
- reclaim the previous slot for the same `clientId` if reconnect happens before the configurable grace period expires

### 4. Firmware-to-browser assignment messages

Add server-to-browser WS messages for session state.

Suggested payloads:

```json
{
  "type": "session",
  "connected": true,
  "slot": 2,
  "maxSlots": 4,
  "hostMode": "usb_xinput"
}
```

```json
{
  "type": "session",
  "connected": false,
  "reason": "full"
}
```

Reasons:

- `assigned`
- `reassigned`
- `full`
- `removed_idle`
- `removed_disconnect`
- `unsupported_mode`

### 5. USB transport abstraction changes

Current host transport is one-report-only. Extend it so USB transports can manage multiple virtual controllers.

Possible interface evolution:

- keep BLE path on the existing single-controller API
- add USB-only multi-controller methods, for example:
  - `setSlotReport(slot, report)`
  - `clearSlot(slot)`
  - `setActiveSlots(mask)`
  - `sendAll(active_reports)`

Pragmatic approach:

- keep `HostTransport` backward-compatible for BLE
- add a new `UsbMultiControllerTransport` interface implemented by both USB transports
- let `HostConnectionManager` fan out active slot reports once per main loop tick

### 6. XInput multi-controller path

Refactor `usb_xinput_gamepad.*` from one global report pipeline to `N` controller functions.

Work items:

- duplicate per-controller driver state:
  - report buffer
  - endpoint addresses
  - in-flight flags
  - dirty flags
  - completion counters
- generate descriptors for multiple controller interfaces
- keep a deterministic mapping between slot number and USB interface/function number
- expose controller removal by sending neutral state and marking slot inactive

Big risk:

- some hosts treat XInput as a special-case transport and may not accept arbitrary composite multi-pad layouts unless descriptors match expected patterns.

Implementation plan should include an early prototype:

- start with 2 controllers
- validate enumeration on the XInput target host first
- then scale to the v1 target of 4 after proof

### 7. Switch multi-controller path

Refactor `usb_switch_gamepad.*` from one `USBHIDDevice` instance to multiple HID gamepad interfaces or multiple reports, depending on what the target host accepts.

Work items:

- create one HID gamepad function per slot
- maintain per-slot report objects
- map slot add/remove to ready/neutral behavior
- test whether target Switch host accepts multiple controllers from one composite device

Risk:

- “USB Switch” may require host-specific expectations that differ from generic HID multi-gamepad support.
- since XInput is the first target, Switch work should stay behind the XInput validation milestone

### 8. Disconnect and idle semantics

Define slot lifecycle clearly.

Recommended policy:

- WebSocket disconnect:
  - immediately neutralize slot
  - start firmware-configurable grace timer
  - keep slot reserved for same `clientId` during grace window
  - after grace window, remove slot fully
- Packet idle timeout:
  - if no packet for `kWsTimeoutMs`, treat it as slot termination
  - neutralize immediately
  - start the same configurable grace timer
  - after grace window, remove slot and free number

This avoids sticky input while still making reconnect less annoying.

Suggested timers:

- input neutralize timeout: keep existing `kWsTimeoutMs` semantics
- reconnect grace: add a firmware config value, with an initial default around 3 to 5 seconds

### 9. Status API changes

Extend `GET /api/status` with multi-controller state.

Suggested additions:

```json
{
  "controller": {
    "maxSlots": 4,
    "activeSlots": 2,
    "clients": [
      {
        "slot": 1,
        "connected": true,
        "idle": false,
        "lastPacketAgeMs": 12
      },
      {
        "slot": 2,
        "connected": true,
        "idle": false,
        "lastPacketAgeMs": 48
      }
    ],
    "thisClient": {
      "slot": 2,
      "connected": true
    }
  }
}
```

For privacy and simplicity:

- do not expose other phones’ stable IDs to browsers by default
- expose only slot occupancy and counts unless admin/debug mode is needed

### 10. UI changes

Add a dedicated status badge/circle to the left of the settings button.

Behavior:

- disconnected or unassigned:
  - hollow or muted circle
  - optional `?`
- connected and assigned:
  - filled circle
  - show controller number
- full / rejected:
  - error styling

Scope:

- show only the local phone's assigned number in the badge
- do not add global occupancy text unless later requested

Needed changes:

- add new DOM node near `#config-open` in [`web/index.html`](/home/htappen/controller/web/index.html)
- style badge in [`web/src/styles.css`](/home/htappen/controller/web/src/styles.css)
- update `GamepadController` to consume server WS session messages
- update `PageStateController` render path to show aggregate occupancy in modal if useful

### 11. Browser controller pipeline

Current browser side only sends control packets. Extend it to:

- persist a browser `clientId`
- send hello/register packet on WS open
- wait for assignment
- surface assigned slot in UI
- preserve current gamepad packet behavior after assignment
- optionally pause control transmission until assigned

Good first rule:

- allow packets immediately after open
- firmware drops them until handshake finishes

### 12. Logging and debug hooks

Add serial logs and status counters for:

- slot assigned
- slot reclaimed
- slot neutralized by timeout
- slot removed by disconnect
- slot rejected because full
- per-slot packet accepted/rejected counts
- USB transport active-slot mask

Needed because debugging multi-controller USB enumeration will be difficult without observability.

## Implementation Phases

### Phase 0. Feasibility spike

Goal: prove host-side USB shape before refactoring whole stack.

Tasks:

- prototype 2-controller composite device for `usb_xinput`
- verify enumeration and independent input on the XInput target host
- defer `usb_switch` prototype work until after XInput feasibility is proven

Exit criteria:

- XInput host sees two independent controllers from one ESP32 composite device

### Phase 1. Firmware multi-session core

Tasks:

- add session manager and multi-slot state store
- add per-slot timeout logic
- refactor `WebServerBridge` away from single `ws_client_connected_`
- add WS handshake and session messages
- extend `/api/status`

Exit criteria:

- firmware can track multiple phones and assign stable slots even before USB transport is upgraded

### Phase 2. USB transport fanout

Tasks:

- extend host transport abstraction for per-slot reports
- implement multi-slot XInput path
- neutralize and remove slots correctly

Deferred follow-up after XInput success:

- implement multi-slot Switch path

Exit criteria:

- 2 or more phones drive distinct host-visible controllers

### Phase 3. Browser UX

Tasks:

- persist client identity
- show assignment badge
- surface full/rejected state
- optionally show total occupancy in config modal

Exit criteria:

- each phone can tell whether it owns a slot and which number it is

### Phase 4. Testing and hardening

Tasks:

- add unit coverage for slot assignment logic
- add protocol tests for hello/session packets
- add host-side transport tests where practical
- extend Pi E2E scripts for multi-phone validation
- validate idle/disconnect cleanup and slot reuse

Exit criteria:

- reconnect, timeout, and removal behavior are deterministic and repeatable

## Concrete Code Changes

### Firmware

Likely new files:

- `firmware/src/controller_session_manager.h`
- `firmware/src/controller_session_manager.cpp`
- `firmware/src/multi_controller_state_store.h`
- `firmware/src/multi_controller_state_store.cpp`

Likely modified files:

- [`firmware/src/main.cpp`](/home/htappen/controller/firmware/src/main.cpp)
- [`firmware/src/web_server.h`](/home/htappen/controller/firmware/src/web_server.h)
- [`firmware/src/web_server.cpp`](/home/htappen/controller/firmware/src/web_server.cpp)
- [`firmware/src/ws_bridge.h`](/home/htappen/controller/firmware/src/ws_bridge.h)
- [`firmware/src/ws_bridge.cpp`](/home/htappen/controller/firmware/src/ws_bridge.cpp)
- [`firmware/src/host_transport.h`](/home/htappen/controller/firmware/src/host_transport.h)
- [`firmware/src/host_connection.h`](/home/htappen/controller/firmware/src/host_connection.h)
- [`firmware/src/host_connection.cpp`](/home/htappen/controller/firmware/src/host_connection.cpp)
- [`firmware/src/usb_xinput_gamepad.h`](/home/htappen/controller/firmware/src/usb_xinput_gamepad.h)
- [`firmware/src/usb_xinput_gamepad.cpp`](/home/htappen/controller/firmware/src/usb_xinput_gamepad.cpp)
- [`firmware/src/usb_switch_gamepad.h`](/home/htappen/controller/firmware/src/usb_switch_gamepad.h)
- [`firmware/src/usb_switch_gamepad.cpp`](/home/htappen/controller/firmware/src/usb_switch_gamepad.cpp)
- [`firmware/src/config.h`](/home/htappen/controller/firmware/src/config.h)

Configuration additions should include:

- max controller slots constant set to 4 for v1
- firmware-configurable reconnect grace period

### Web UI

Likely modified files:

- [`web/index.html`](/home/htappen/controller/web/index.html)
- [`web/src/main.js`](/home/htappen/controller/web/src/main.js)
- [`web/src/page_state_controller.js`](/home/htappen/controller/web/src/page_state_controller.js)
- [`web/src/gamepad_controller.js`](/home/htappen/controller/web/src/gamepad_controller.js)
- [`web/src/styles.css`](/home/htappen/controller/web/src/styles.css)
- [`web/src/schema.js`](/home/htappen/controller/web/src/schema.js)

### Docs and tests

Likely modified or added:

- [`docs/protocol.md`](/home/htappen/controller/docs/protocol.md)
- [`docs/architecture.md`](/home/htappen/controller/docs/architecture.md)
- new host-side tests under `test/`
- Pi E2E scripts under `tools/pi/`

## Testing Plan

### Unit and protocol tests

- slot assignment order
- slot reuse after disconnect
- reclaim same slot on quick reconnect with same `clientId`
- reject extra client when full
- neutralize on packet timeout
- evict on long idle
- ignore stale `seq` within one slot
- keep one client’s stale packet from affecting another slot

### Firmware and browser integration

- connect phone A, get slot 1
- connect phone B, get slot 2
- disconnect phone A, slot 1 neutralizes and later frees
- reconnect phone A during grace window, regains slot 1
- leave phone B idle, slot 2 neutralizes then evicts
- open fifth phone when max is 4, show full-state badge

### Host-side USB validation

For XInput first:

- host enumerates correct number of controllers
- controller 1 input only moves controller 1 on host
- controller 2 input only moves controller 2 on host
- removing one phone does not disturb remaining active controllers more than necessary
- re-adding a phone restores a usable controller slot

Follow-up after XInput passes:

- repeat equivalent validation for Switch mode

## Risks

1. XInput multi-controller compatibility may be constrained by host expectations, not just descriptor correctness.
2. Switch host mode may not accept multiple controller interfaces from one composite device.
3. WebSocket client numbering alone is not stable enough; browser identity handshake is required.
4. Multi-controller USB descriptors will make debugging enumeration failures much harder than current single-controller setup.

## Recommended Delivery Order

1. Prove composite multi-controller enumeration with 2 controllers on XInput first.
2. Build firmware session manager and per-slot state handling.
3. Connect session manager to USB transport fanout.
4. Add browser handshake and assignment UI.
5. Expand to 4 controllers after 2-controller path is solid.
6. Port the proven design to Switch mode after XInput.
