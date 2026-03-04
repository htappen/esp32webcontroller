#pragma once

#include <stdint.h>

#include <BleGamepad.h>

#include "input_mapper.h"

class BleGamepadBridge {
 public:
  BleGamepadBridge();
  bool begin();
  bool connected();
  void setAdvertisingEnabled(bool enabled);
  bool advertisingEnabled() const;
  void send(const BleReport& report);

 private:
  static int8_t toHatValue(const Buttons& btn);
  static int16_t toTriggerAxis(uint8_t trigger);

  BleGamepad ble_;
  bool started_ = false;
  bool advertising_enabled_ = true;
};
