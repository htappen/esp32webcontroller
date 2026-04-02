#include "ble_gamepad.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "config.h"

namespace {
constexpr int16_t kAxisMin = -32767;
constexpr int16_t kAxisMax = 32767;
constexpr int16_t kTriggerMax = 32767;
constexpr uint16_t kPreferredConnIntervalMin = 24;
constexpr uint16_t kPreferredConnIntervalMax = 48;
constexpr uint16_t kAdvertisingInterval = 160;
#if defined(CONTROLLER_BOARD_WROOM)
constexpr uint32_t kAdvertisingInitialDelayMs = 1000;
constexpr uint32_t kAdvertisingRetryMs = 1000;
#elif defined(CONTROLLER_BOARD_S3)
constexpr uint32_t kAdvertisingInitialDelayMs = 1000;
constexpr uint32_t kAdvertisingRetryMs = 1000;
#endif

void configureAdvertising() {
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr) {
    Serial.println("BLE advertising handle unavailable after init");
    return;
  }

  advertising->enableScanResponse(true);
  advertising->setScanFilter(false, false);
  advertising->setAdvertisingInterval(kAdvertisingInterval);
  advertising->setPreferredParams(kPreferredConnIntervalMin, kPreferredConnIntervalMax);
  advertising->setConnectableMode(BLE_GAP_CONN_MODE_UND);
  advertising->setDiscoverableMode(BLE_GAP_DISC_MODE_GEN);
}
}  // namespace

BleGamepadBridge::BleGamepadBridge() : ble_(config::kBleDeviceName, config::kFriendlyName, 100, true) {}

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
#if defined(CONTROLLER_BOARD_S3)
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  if (!NimBLEDevice::setOwnAddrType(BLE_OWN_ADDR_PUBLIC)) {
    Serial.println("BLE failed to force public address type on S3");
  }
  configureAdvertising();
#endif
  started_ = true;
  next_advertising_attempt_ms_ = millis() + kAdvertisingInitialDelayMs;
#if defined(CONTROLLER_BOARD_S3)
  Serial.printf("BLE host ready: addr=%s board=%s\n", NimBLEDevice::getAddress().toString().c_str(),
                config::kBoardName);
#else
  Serial.printf("BLE host ready: board=%s\n", config::kBoardName);
#endif
  return true;
}

void BleGamepadBridge::loop() {
  if (!started_) {
    return;
  }

  if (!advertising_enabled_ || ble_.isConnected()) {
    return;
  }

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr || advertising->isAdvertising()) {
    return;
  }

  const uint32_t now = millis();
  if (static_cast<int32_t>(now - next_advertising_attempt_ms_) < 0) {
    return;
  }

  if (advertising->start()) {
#if defined(CONTROLLER_BOARD_S3)
    Serial.printf("BLE advertising started: board=%s addr=%s\n", config::kBoardName,
                  NimBLEDevice::getAddress().toString().c_str());
#else
    Serial.printf("BLE advertising started: board=%s\n", config::kBoardName);
#endif
    next_advertising_attempt_ms_ = now;
    return;
  }

  Serial.printf("BLE advertising start failed; retrying in %lu ms\n", static_cast<unsigned long>(kAdvertisingRetryMs));
  next_advertising_attempt_ms_ = now + kAdvertisingRetryMs;
}

bool BleGamepadBridge::connected() const {
  return started_ && const_cast<BleGamepad&>(ble_).isConnected();
}

bool BleGamepadBridge::forgetCurrentBond() {
  if (!started_ || !ble_.isConnected()) {
    return false;
  }

  NimBLEServer* server = NimBLEDevice::getServer();
  if (server == nullptr) {
    return false;
  }

  NimBLEConnInfo peer = server->getPeerInfo(0);
  const uint16_t conn_handle = peer.getConnHandle();
  if (!ble_.deleteBond()) {
    return false;
  }

  server->disconnect(conn_handle);
  next_advertising_attempt_ms_ = millis() + kAdvertisingInitialDelayMs;
  return true;
}

bool BleGamepadBridge::resetConnection() {
  return forgetCurrentBond();
}

bool BleGamepadBridge::setPairingEnabled(bool enabled) {
  setAdvertisingEnabled(enabled);
  return true;
}

void BleGamepadBridge::setAdvertisingEnabled(bool enabled) {
  advertising_enabled_ = enabled;
  next_advertising_attempt_ms_ = millis() + kAdvertisingInitialDelayMs;
  if (!started_) {
    return;
  }

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr) {
    return;
  }

  if (enabled) {
    return;
  } else {
    Serial.println("BLE advertising disabled");
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

bool BleGamepadBridge::send(const HostInputReport& report) {
  if (!connected()) {
    return false;
  }

  // Map to an Xbox-like logical layout over generic HID buttons.
  if (report.btn.a) ble_.press(BUTTON_1); else ble_.release(BUTTON_1);
  if (report.btn.b) ble_.press(BUTTON_2); else ble_.release(BUTTON_2);
  if (report.btn.x) ble_.press(BUTTON_3); else ble_.release(BUTTON_3);
  if (report.btn.y) ble_.press(BUTTON_4); else ble_.release(BUTTON_4);
  if (report.btn.lb) ble_.press(BUTTON_5); else ble_.release(BUTTON_5);
  if (report.btn.rb) ble_.press(BUTTON_6); else ble_.release(BUTTON_6);
  //if (report.btn.back) ble_.press(BUTTON_7); else ble_.release(BUTTON_7);
  //if (report.btn.start) ble_.press(BUTTON_8); else ble_.release(BUTTON_8);
  if (report.btn.back) ble_.pressSelect(); else ble_.releaseSelect();
  if (report.btn.start) ble_.pressStart(); else ble_.releaseStart();
  if (report.btn.ls) ble_.press(BUTTON_9); else ble_.release(BUTTON_9);
  if (report.btn.rs) ble_.press(BUTTON_10); else ble_.release(BUTTON_10);

  ble_.setLeftThumb(report.lx, report.ly);
  ble_.setRightThumb(report.rx, report.ry);
  ble_.setTriggers(toTriggerAxis(report.lt), toTriggerAxis(report.rt));
  ble_.setHat1(toHatValue(report.btn));
  ble_.sendReport();
  return true;
}

HostStatus BleGamepadBridge::status() const {
  HostStatus status;
  status.transport = "ble";
  status.variant = "default";
  status.display_name = config::kBleDeviceName;
  status.ready = started_;
  status.connected = connected();
  status.supports_pairing = true;
  status.pairing_enabled = advertising_enabled_;
  status.advertising = advertisingEnabled();
  return status;
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
