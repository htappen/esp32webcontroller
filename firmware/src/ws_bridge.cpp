#include "ws_bridge.h"

#include <string.h>

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

bool parse_axis(JsonVariantConst value, float* out) {
  if (out == nullptr || value.isNull()) {
    return false;
  }
  if (value.is<float>() || value.is<double>() || value.is<int>() || value.is<long>() ||
      value.is<unsigned int>() || value.is<unsigned long>()) {
    *out = value.as<float>();
    return true;
  }
  return false;
}

void apply_button_if_present(JsonVariantConst object, const char* key, bool* out) {
  if (out == nullptr) {
    return;
  }
  const JsonVariantConst value = object[key];
  if (!value.isNull()) {
    *out = parse_button(value);
  }
}

void apply_axis_if_present(JsonVariantConst object, const char* key, float* out) {
  float parsed = 0.0f;
  if (parse_axis(object[key], &parsed) && out != nullptr) {
    *out = parsed;
  }
}
}  // namespace

bool WsBridge::parseHello(const char* payload, WsHelloPacket* out) const {
  if (payload == nullptr || out == nullptr) {
    return false;
  }

  JsonDocument doc;
  const auto err = deserializeJson(doc, payload);
  if (err) {
    return false;
  }

  const char* type = doc["type"] | "";
  const char* client_id = doc["clientId"] | "";
  if (strcmp(type, "hello") != 0 || client_id[0] == '\0') {
    return false;
  }

  strncpy(out->client_id, client_id, sizeof(out->client_id) - 1);
  out->client_id[sizeof(out->client_id) - 1] = '\0';
  return true;
}

bool WsBridge::parseJson(const char* payload, const ControllerState& base, ControllerState* out) const {
  if (payload == nullptr || out == nullptr) {
    return false;
  }

  JsonDocument doc;
  const auto err = deserializeJson(doc, payload);
  if (err) {
    return false;
  }

  ControllerState state = base;
  state.t = doc["t"] | 0;
  state.seq = doc["seq"] | 0;

  JsonVariantConst btn = doc["btn"];
  apply_button_if_present(btn, "a", &state.btn.a);
  apply_button_if_present(btn, "b", &state.btn.b);
  apply_button_if_present(btn, "x", &state.btn.x);
  apply_button_if_present(btn, "y", &state.btn.y);
  apply_button_if_present(btn, "lb", &state.btn.lb);
  apply_button_if_present(btn, "rb", &state.btn.rb);
  apply_button_if_present(btn, "back", &state.btn.back);
  apply_button_if_present(btn, "start", &state.btn.start);
  apply_button_if_present(btn, "ls", &state.btn.ls);
  apply_button_if_present(btn, "rs", &state.btn.rs);
  apply_button_if_present(btn, "du", &state.btn.du);
  apply_button_if_present(btn, "dd", &state.btn.dd);
  apply_button_if_present(btn, "dl", &state.btn.dl);
  apply_button_if_present(btn, "dr", &state.btn.dr);

  JsonVariantConst ax = doc["ax"];
  apply_axis_if_present(ax, "lx", &state.ax.lx);
  apply_axis_if_present(ax, "ly", &state.ax.ly);
  apply_axis_if_present(ax, "rx", &state.ax.rx);
  apply_axis_if_present(ax, "ry", &state.ax.ry);
  apply_axis_if_present(ax, "lt", &state.ax.lt);
  apply_axis_if_present(ax, "rt", &state.ax.rt);

  *out = state;
  return true;
}
