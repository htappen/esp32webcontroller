# Architecture

## Data Path

1. Phone loads controller UI from ESP32 web server.
2. `virtual-gamepad-lib` emits normalized controller state in browser.
3. Browser sends packets over WebSocket to ESP32.
4. ESP32 validates packets and updates canonical state.
5. Mapper converts state to BLE HID gamepad report.
6. BLE task transmits report to connected host.

## Runtime Components

- `web_server.*`: HTTP + WebSocket transport.
- `network_manager.*`: AP/STA/AP+STA mode control and network status.
- `host_connection.*`: BLE pairing/discoverability and host link status.
- `ws_bridge.*`: packet parsing/validation.
- `state_store.*`: latest controller state and timestamps.
- `input_mapper.*`: maps normalized values to HID range.
- `ble_gamepad.*`: BLE HID advertising, connection state, and report send.

## Safety

- Neutralize controls on WebSocket timeout.
- Neutralize controls on BLE disconnect.
- Ignore out-of-order packet sequence numbers.
