#include "host_connection.h"

bool HostConnectionManager::begin() {
  if (!ble_.begin()) {
    return false;
  }
  ble_.setAdvertisingEnabled(pairing_enabled_);
  status_.advertising = ble_.advertisingEnabled();
  status_.connected = ble_.connected();
  return true;
}

void HostConnectionManager::loop() {
  status_.connected = ble_.connected();
  status_.advertising = ble_.advertisingEnabled();
}

void HostConnectionManager::setPairingEnabled(bool enabled) {
  pairing_enabled_ = enabled;
  ble_.setAdvertisingEnabled(enabled);
  status_.advertising = ble_.advertisingEnabled();
}

HostStatus HostConnectionManager::status() const {
  return status_;
}

BleGamepadBridge* HostConnectionManager::bridge() {
  return &ble_;
}
