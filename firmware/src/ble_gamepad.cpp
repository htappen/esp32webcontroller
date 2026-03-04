#include "ble_gamepad.h"

#include <NimBLEDevice.h>

#include "config.h"

namespace {
constexpr int16_t kAxisMin = -32767;
constexpr int16_t kAxisMax = 32767;
constexpr int16_t kTriggerMax = 32767;
}  // namespace

BleGamepadBridge::BleGamepadBridge() : ble_(config::kBleDeviceName, "ESP32 Web BLE Controller", 100, true) {}

bool BleGamepadBridge::begin() {
  BleGamepadConfiguration cfg;
  cfg.setControllerType(CONTROLLER_TYPE_GAMEPAD);
  cfg.setButtonCount(16);
  cfg.setHatSwitchCount(1);
  cfg.setAxesMin(kAxisMin);
  cfg.setAxesMax(kAxisMax);
  cfg.setAutoReport(false);
  cfg.setIncludeStart(true);
  cfg.setIncludeSelect(true);
  cfg.setEnableOutputReport(false);

  ble_.begin(&cfg);
  started_ = true;
  setAdvertisingEnabled(advertising_enabled_);
  return true;
}

bool BleGamepadBridge::connected() {
  return started_ && ble_.isConnected();
}

void BleGamepadBridge::setAdvertisingEnabled(bool enabled) {
  advertising_enabled_ = enabled;
  if (!started_) {
    return;
  }

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr) {
    return;
  }

  if (enabled) {
    if (!ble_.isConnected()) {
      advertising->start();
    }
  } else {
    advertising->stop();
  }
}

bool BleGamepadBridge::advertisingEnabled() const {
  if (!started_) {
    return advertising_enabled_;
  }
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  return advertising_enabled_ && advertising != nullptr && advertising->isAdvertising();
}

void BleGamepadBridge::send(const BleReport& report) {
  if (!connected()) {
    return;
  }

  // Map to an Xbox-like logical layout over generic HID buttons.
  if (report.btn.a) ble_.press(BUTTON_1); else ble_.release(BUTTON_1);
  if (report.btn.b) ble_.press(BUTTON_2); else ble_.release(BUTTON_2);
  if (report.btn.x) ble_.press(BUTTON_3); else ble_.release(BUTTON_3);
  if (report.btn.y) ble_.press(BUTTON_4); else ble_.release(BUTTON_4);
  if (report.btn.lb) ble_.press(BUTTON_5); else ble_.release(BUTTON_5);
  if (report.btn.rb) ble_.press(BUTTON_6); else ble_.release(BUTTON_6);
  if (report.btn.back) ble_.press(BUTTON_7); else ble_.release(BUTTON_7);
  if (report.btn.start) ble_.press(BUTTON_8); else ble_.release(BUTTON_8);
  if (report.btn.ls) ble_.press(BUTTON_9); else ble_.release(BUTTON_9);
  if (report.btn.rs) ble_.press(BUTTON_10); else ble_.release(BUTTON_10);

  ble_.setLeftThumb(report.lx, report.ly);
  ble_.setRightThumb(report.rx, report.ry);
  ble_.setTriggers(toTriggerAxis(report.lt), toTriggerAxis(report.rt));
  ble_.setHat1(toHatValue(report.btn));
  ble_.sendReport();
}

int8_t BleGamepadBridge::toHatValue(const Buttons& btn) {
  const bool up = btn.du;
  const bool down = btn.dd;
  const bool left = btn.dl;
  const bool right = btn.dr;

  if (up && right) return HAT_UP_RIGHT;
  if (up && left) return HAT_UP_LEFT;
  if (down && right) return HAT_DOWN_RIGHT;
  if (down && left) return HAT_DOWN_LEFT;
  if (up) return HAT_UP;
  if (down) return HAT_DOWN;
  if (right) return HAT_RIGHT;
  if (left) return HAT_LEFT;
  return HAT_CENTERED;
}

int16_t BleGamepadBridge::toTriggerAxis(uint8_t trigger) {
  return static_cast<int16_t>((static_cast<uint32_t>(trigger) * kTriggerMax) / 255u);
}
