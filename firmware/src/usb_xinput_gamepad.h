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
  bool sendSlots(const HostInputReport* reports, uint8_t report_count, uint32_t active_slot_mask) override;
 HostStatus status() const override;

 private:
  bool started_ = false;
  bool deferred_start_ = false;
};

#endif
