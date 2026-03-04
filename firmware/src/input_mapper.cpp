#include "input_mapper.h"

namespace {
static int16_t to_axis(float v) {
  if (v > 1.0f) v = 1.0f;
  if (v < -1.0f) v = -1.0f;
  return static_cast<int16_t>(v * 32767.0f);
}

static uint8_t to_trigger(float v) {
  if (v > 1.0f) v = 1.0f;
  if (v < 0.0f) v = 0.0f;
  return static_cast<uint8_t>(v * 255.0f);
}
}  // namespace

BleReport InputMapper::map(const ControllerState& in) {
  BleReport out;
  out.lx = to_axis(in.ax.lx);
  out.ly = to_axis(in.ax.ly);
  out.rx = to_axis(in.ax.rx);
  out.ry = to_axis(in.ax.ry);
  out.lt = to_trigger(in.ax.lt);
  out.rt = to_trigger(in.ax.rt);
  out.btn = in.btn;
  return out;
}
