#pragma once

#include <ArduinoJson.h>

#include "state_store.h"

class WsBridge {
 public:
  bool parseJson(const char* payload, ControllerState* out) const;
};
