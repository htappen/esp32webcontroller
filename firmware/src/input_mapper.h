#pragma once

// Maps normalized web controller state into BLE HID axis/button report values.

#include <stdint.h>

#include "state_store.h"

struct BleReport {
  int16_t lx = 0;
  int16_t ly = 0;
  int16_t rx = 0;
  int16_t ry = 0;
  uint8_t lt = 0;
  uint8_t rt = 0;
  Buttons btn;
};

class InputMapper {
 public:
  static BleReport map(const ControllerState& in);
};
