#pragma once

#include "input_mapper.h"

struct HostStatus {
  const char* transport = "ble";
  const char* variant = "default";
  const char* display_name = "";
  bool ready = false;
  bool connected = false;
  bool supports_pairing = false;
  bool pairing_enabled = false;
  bool advertising = false;
};

class HostTransport {
 public:
  virtual ~HostTransport() = default;

  virtual bool begin() = 0;
  virtual void loop() = 0;
  virtual bool resetConnection() = 0;
  virtual bool setPairingEnabled(bool enabled) = 0;
  virtual bool send(const HostInputReport& report) = 0;
  virtual HostStatus status() const = 0;
};
