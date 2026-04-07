#pragma once

#include "host_transport.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)

class UsbXInputGamepadBridge : public HostTransport {
 public:
  bool begin() override;
  void loop() override;
  bool resetConnection() override;
  bool setPairingEnabled(bool enabled) override;
  bool send(const HostInputReport& report) override;
 HostStatus status() const override;

 private:
  bool started_ = false;
  bool deferred_start_ = false;
};

#endif
