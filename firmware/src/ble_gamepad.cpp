#include "ble_gamepad.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "config.h"

namespace {
constexpr uint16_t kPreferredConnIntervalMin = 24;
constexpr uint16_t kPreferredConnIntervalMax = 48;
constexpr uint16_t kAdvertisingInterval = 160;
constexpr uint32_t kAdvertisingInitialDelayMs = 1000;
constexpr uint32_t kAdvertisingRetryMs = 1000;
}  // namespace

BleGamepadBridge::BleGamepadBridge() : ble_(config::kBleDeviceName, config::kFriendlyName, 100) {
  ble_.addDevice(&xbox_);
}

bool BleGamepadBridge::begin() {
  const auto* device_config =
      static_cast<const XboxGamepadDeviceConfiguration*>(xbox_.getDeviceConfig());
  BLEHostConfiguration host_config = device_config->getIdealHostConfiguration();
  host_config.setQueuedSending(false);
  ble_.begin(host_config);

  started_ = true;
  advertising_configured_ = false;
  next_advertising_attempt_ms_ = millis() + kAdvertisingInitialDelayMs;
  Serial.printf("BLE host ready: board=%s profile=xbox-one-s\n", config::kBoardName);
  return true;
}

void BleGamepadBridge::loop() {
  if (!started_) {
    return;
  }

  if (!advertising_configured_) {
    configureAdvertising();
  }

  if (!advertising_enabled_ || connected()) {
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
    Serial.printf("BLE advertising started: board=%s profile=xbox-one-s\n", config::kBoardName);
    next_advertising_attempt_ms_ = now;
    return;
  }

  Serial.printf("BLE advertising start failed; retrying in %lu ms\n",
                static_cast<unsigned long>(kAdvertisingRetryMs));
  next_advertising_attempt_ms_ = now + kAdvertisingRetryMs;
}

void BleGamepadBridge::configureAdvertising() {
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr) {
    return;
  }

  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
#if defined(CONTROLLER_BOARD_S3)
  if (!NimBLEDevice::setOwnAddrType(BLE_OWN_ADDR_PUBLIC)) {
    Serial.println("BLE failed to force public address type on S3");
  }
#endif
  advertising->enableScanResponse(true);
  advertising->setScanFilter(false, false);
  advertising->setAdvertisingInterval(kAdvertisingInterval);
  advertising->setPreferredParams(kPreferredConnIntervalMin, kPreferredConnIntervalMax);
  advertising->setConnectableMode(BLE_GAP_CONN_MODE_UND);
  advertising->setDiscoverableMode(BLE_GAP_DISC_MODE_GEN);
  advertising_configured_ = true;
}

bool BleGamepadBridge::connected() const {
  return started_ && const_cast<BleCompositeHID&>(ble_).isConnected();
}

bool BleGamepadBridge::forgetCurrentBond() {
  if (!started_ || !connected()) {
    return false;
  }

  NimBLEServer* server = NimBLEDevice::getServer();
  if (server == nullptr) {
    return false;
  }

  NimBLEConnInfo peer = server->getPeerInfo(0);
  const uint16_t conn_handle = peer.getConnHandle();
  server->disconnect(conn_handle);
  NimBLEDevice::deleteAllBonds();
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

  NimBLEServer* server = NimBLEDevice::getServer();
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (server == nullptr || advertising == nullptr) {
    return;
  }

  server->advertiseOnDisconnect(enabled);
  if (!enabled) {
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

  if (report.btn.a) xbox_.press(XBOX_BUTTON_A); else xbox_.release(XBOX_BUTTON_A);
  if (report.btn.b) xbox_.press(XBOX_BUTTON_B); else xbox_.release(XBOX_BUTTON_B);
  if (report.btn.x) xbox_.press(XBOX_BUTTON_X); else xbox_.release(XBOX_BUTTON_X);
  if (report.btn.y) xbox_.press(XBOX_BUTTON_Y); else xbox_.release(XBOX_BUTTON_Y);
  if (report.btn.lb) xbox_.press(XBOX_BUTTON_LB); else xbox_.release(XBOX_BUTTON_LB);
  if (report.btn.rb) xbox_.press(XBOX_BUTTON_RB); else xbox_.release(XBOX_BUTTON_RB);
  if (report.btn.back) xbox_.press(XBOX_BUTTON_SELECT); else xbox_.release(XBOX_BUTTON_SELECT);
  if (report.btn.start) xbox_.press(XBOX_BUTTON_START); else xbox_.release(XBOX_BUTTON_START);

  xbox_.setLeftThumb(report.lx, report.ly);
  xbox_.setRightThumb(report.rx, report.ry);
  xbox_.setTriggers(toTriggerAxis(report.lt), toTriggerAxis(report.rt));
  xbox_.pressDPadDirection(toHatValue(report.btn));
  xbox_.sendGamepadReport();
  return true;
}

HostStatus BleGamepadBridge::status() const {
  HostStatus status;
  status.transport = "ble";
  status.variant = "xbox-one-s";
  status.display_name = config::kBleDeviceName;
  status.ready = started_;
  status.connected = connected();
  status.supports_pairing = true;
  status.pairing_enabled = advertising_enabled_;
  status.advertising = advertisingEnabled();
  return status;
}

uint8_t BleGamepadBridge::toHatValue(const Buttons& btn) {
  const uint8_t up = btn.du ? NORTH : 0;
  const uint8_t down = btn.dd ? SOUTH : 0;
  const uint8_t left = btn.dl ? WEST : 0;
  const uint8_t right = btn.dr ? EAST : 0;
  return dPadDirectionToValue(static_cast<XboxDpadFlags>(up | down | left | right));
}

uint16_t BleGamepadBridge::toTriggerAxis(uint8_t trigger) {
  return static_cast<uint16_t>((static_cast<uint32_t>(trigger) * XBOX_TRIGGER_MAX) / 255u);
}
