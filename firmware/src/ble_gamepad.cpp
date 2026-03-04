#include "ble_gamepad.h"

bool BleGamepadBridge::begin() {
  // TODO: initialize NimBLE + HID report descriptor.
  return true;
}

bool BleGamepadBridge::connected() const {
  // TODO: return real BLE connection status.
  return false;
}

void BleGamepadBridge::setAdvertisingEnabled(bool enabled) {
  advertising_enabled_ = enabled;
  // TODO: start/stop BLE advertising based on enabled state.
}

bool BleGamepadBridge::advertisingEnabled() const {
  return advertising_enabled_;
}

void BleGamepadBridge::send(const BleReport& report) {
  (void)report;
  // TODO: encode and send HID input report.
}
