#pragma once

// Canonical in-memory controller state shared between transport and BLE tasks.

#include <stdint.h>

struct Buttons {
  bool a = false;
  bool b = false;
  bool x = false;
  bool y = false;
  bool lb = false;
  bool rb = false;
  bool back = false;
  bool start = false;
  bool ls = false;
  bool rs = false;
  bool du = false;
  bool dd = false;
  bool dl = false;
  bool dr = false;
};

struct Axes {
  float lx = 0.0f;
  float ly = 0.0f;
  float rx = 0.0f;
  float ry = 0.0f;
  float lt = 0.0f;
  float rt = 0.0f;
};

struct ControllerState {
  uint32_t seq = 0;
  uint32_t t = 0;
  Buttons btn;
  Axes ax;
  uint32_t last_update_ms = 0;
};

class StateStore {
 public:
  bool reset();
  bool apply(const ControllerState& next);
  ControllerState snapshot() const;

 private:
  ControllerState state_;
};
