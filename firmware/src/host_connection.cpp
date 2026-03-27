#include "host_connection.h"

HostConnectionManager::HostConnectionManager(DeviceSettingsStore* settings) : settings_(settings) {}

bool HostConnectionManager::begin() {
  if (settings_ != nullptr) {
    const DeviceRuntimeSettings runtime = settings_->loadRuntimeSettings();
    pairing_enabled_ = runtime.pairing_enabled;
  }
  if (!ble_.begin()) {
    return false;
  }
  ble_.setAdvertisingEnabled(pairing_enabled_);
  refreshStatus();
  return true;
}

void HostConnectionManager::loop() {
  ble_.loop();
  refreshStatus();
}

bool HostConnectionManager::forgetCurrentHost() {
  const bool forgotten = ble_.forgetCurrentBond();
  refreshStatus();
  return forgotten;
}

bool HostConnectionManager::setPairingEnabled(bool enabled) {
  const bool previous = pairing_enabled_;
  bool saved = true;
  if (settings_ != nullptr) {
    DeviceRuntimeSettings runtime;
    runtime.pairing_enabled = enabled;
    saved = settings_->saveRuntimeSettings(runtime);
  }

  if (!saved) {
    pairing_enabled_ = previous;
    ble_.setAdvertisingEnabled(previous);
    refreshStatus();
    return false;
  }

  pairing_enabled_ = enabled;
  ble_.setAdvertisingEnabled(enabled);
  refreshStatus();
  return saved;
}

HostStatus HostConnectionManager::status() const {
  return status_;
}

BleGamepadBridge* HostConnectionManager::bridge() {
  return &ble_;
}

void HostConnectionManager::refreshStatus() {
  status_.connected = ble_.connected();
  status_.advertising = ble_.advertisingEnabled();
  status_.pairing_enabled = pairing_enabled_;
}
