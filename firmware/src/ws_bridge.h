#pragma once

// JSON parser bridge that translates incoming WebSocket payloads into ControllerState.

#include <ArduinoJson.h>

#include "state_store.h"

class WsBridge {
 public:
  bool parseJson(const char* payload, const ControllerState& base, ControllerState* out) const;
};
