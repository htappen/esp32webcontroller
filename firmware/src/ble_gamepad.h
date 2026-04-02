#pragma once

// BLE HID gamepad adapter used to publish mapped controller reports to a host.

#include <stdint.h>

#include <BleCompositeHID.h>
#include <XboxGamepadDevice.h>

#include "host_transport.h"

class BleGamepadBridge : public HostTransport {
 public:
  BleGamepadBridge();
  bool begin() override;
  void loop() override;
  bool resetConnection() override;
  bool setPairingEnabled(bool enabled) override;
  bool send(const HostInputReport& report) override;
  HostStatus status() const override;

 private:
  static uint8_t toHatValue(const Buttons& btn);
  static uint16_t toTriggerAxis(uint8_t trigger);
  void configureAdvertising();
  bool connected() const;
  bool forgetCurrentBond();
  void setAdvertisingEnabled(bool enabled);
  bool advertisingEnabled() const;

  BleCompositeHID ble_;
  XboxGamepadDevice xbox_;
  bool started_ = false;
  bool advertising_enabled_ = true;
  bool advertising_configured_ = false;
  uint32_t next_advertising_attempt_ms_ = 0;
};
