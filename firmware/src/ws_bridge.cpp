#include "ws_bridge.h"

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
  state.btn.a = btn["a"] | false;
  state.btn.b = btn["b"] | false;
  state.btn.x = btn["x"] | false;
  state.btn.y = btn["y"] | false;
  state.btn.lb = btn["lb"] | false;
  state.btn.rb = btn["rb"] | false;
  state.btn.back = btn["back"] | false;
  state.btn.start = btn["start"] | false;
  state.btn.ls = btn["ls"] | false;
  state.btn.rs = btn["rs"] | false;
  state.btn.du = btn["du"] | false;
  state.btn.dd = btn["dd"] | false;
  state.btn.dl = btn["dl"] | false;
  state.btn.dr = btn["dr"] | false;

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
