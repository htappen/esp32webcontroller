#pragma once

// JSON parser bridge that translates incoming WebSocket payloads into ControllerState.

#include <ArduinoJson.h>

#include "state_store.h"

struct WsHelloPacket {
  char client_id[37] = {};
};

class WsBridge {
 public:
  bool parseHello(const char* payload, WsHelloPacket* out) const;
  bool parseJson(const char* payload, const ControllerState& base, ControllerState* out) const;
};
