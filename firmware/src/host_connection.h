#pragma once

// Host link manager that owns the active host transport and exposes its status.

#include "device_settings.h"
#include "host_transport.h"

class HostConnectionManager {
 public:
  explicit HostConnectionManager(DeviceSettingsStore* settings = nullptr);
  bool begin();
  void loop();

  bool forgetCurrentHost();
  bool setPairingEnabled(bool enabled);
  bool sendReport(const HostInputReport& report);
  HostStatus status() const;

 private:
  void refreshStatus();

  DeviceSettingsStore* settings_ = nullptr;
  HostTransport* transport_ = nullptr;
  HostStatus status_;
  bool pairing_enabled_ = true;
};
