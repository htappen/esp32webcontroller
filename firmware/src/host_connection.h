#pragma once

// Host link manager that owns the BLE bridge and exposes pairing/connection state.

#include "ble_gamepad.h"
#include "device_settings.h"

struct HostStatus {
  bool advertising = false;
  bool connected = false;
  bool pairing_enabled = true;
};

class HostConnectionManager {
 public:
  explicit HostConnectionManager(DeviceSettingsStore* settings = nullptr);
  bool begin();
  void loop();

  bool forgetCurrentHost();
  bool setPairingEnabled(bool enabled);
  HostStatus status() const;

  BleGamepadBridge* bridge();

 private:
  void refreshStatus();

  DeviceSettingsStore* settings_ = nullptr;
  BleGamepadBridge ble_;
  HostStatus status_;
  bool pairing_enabled_ = true;
};
