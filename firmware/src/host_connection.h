#pragma once

// Host link manager that owns the BLE bridge and exposes pairing/connection state.

#include "ble_gamepad.h"

struct HostStatus {
  bool advertising = false;
  bool connected = false;
};

class HostConnectionManager {
 public:
  bool begin();
  void loop();

  bool forgetCurrentHost();
  void setPairingEnabled(bool enabled);
  HostStatus status() const;

  BleGamepadBridge* bridge();

 private:
  BleGamepadBridge ble_;
  HostStatus status_;
  bool pairing_enabled_ = true;
};
