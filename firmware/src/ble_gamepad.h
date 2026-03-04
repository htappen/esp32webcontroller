#pragma once

#include "input_mapper.h"

class BleGamepadBridge {
 public:
  bool begin();
  bool connected() const;
  void setAdvertisingEnabled(bool enabled);
  bool advertisingEnabled() const;
  void send(const BleReport& report);

 private:
  bool advertising_enabled_ = true;
};
