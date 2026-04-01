#pragma once

#include "host_transport.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)

class UsbSwitchGamepadBridge : public HostTransport {
 public:
  bool begin() override;
  void loop() override;
  bool resetConnection() override;
  bool setPairingEnabled(bool enabled) override;
  bool send(const HostInputReport& report) override;
  HostStatus status() const override;

 private:
  bool started_ = false;
};

#endif
