#include "ws_bridge.h"

namespace {
bool parse_button(JsonVariantConst value) {
  if (value.is<bool>()) {
    return value.as<bool>();
  }
  if (value.is<int>()) {
    return value.as<int>() != 0;
  }
  if (value.is<unsigned int>()) {
    return value.as<unsigned int>() != 0;
  }
  if (value.is<long>()) {
    return value.as<long>() != 0;
  }
  if (value.is<unsigned long>()) {
    return value.as<unsigned long>() != 0;
  }
  return false;
}
}  // namespace

bool WsBridge::parseJson(const char* payload, ControllerState* out) const {
  if (payload == nullptr || out == nullptr) {
    return false;
  }

  JsonDocument doc;
  const auto err = deserializeJson(doc, payload);
  if (err) {
    return false;
  }

  ControllerState state;
  state.t = doc["t"] | 0;
  state.seq = doc["seq"] | 0;

  JsonVariantConst btn = doc["btn"];
  state.btn.a = parse_button(btn["a"]);
  state.btn.b = parse_button(btn["b"]);
  state.btn.x = parse_button(btn["x"]);
  state.btn.y = parse_button(btn["y"]);
  state.btn.lb = parse_button(btn["lb"]);
  state.btn.rb = parse_button(btn["rb"]);
  state.btn.back = parse_button(btn["back"]);
  state.btn.start = parse_button(btn["start"]);
  state.btn.ls = parse_button(btn["ls"]);
  state.btn.rs = parse_button(btn["rs"]);
  state.btn.du = parse_button(btn["du"]);
  state.btn.dd = parse_button(btn["dd"]);
  state.btn.dl = parse_button(btn["dl"]);
  state.btn.dr = parse_button(btn["dr"]);

  JsonVariantConst ax = doc["ax"];
  state.ax.lx = ax["lx"] | 0.0f;
  state.ax.ly = ax["ly"] | 0.0f;
  state.ax.rx = ax["rx"] | 0.0f;
  state.ax.ry = ax["ry"] | 0.0f;
  state.ax.lt = ax["lt"] | 0.0f;
  state.ax.rt = ax["rt"] | 0.0f;

  *out = state;
  return true;
}
