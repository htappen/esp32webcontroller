#pragma once

// Centralized firmware-level constants for networking, timing, and host identity.

#include <stdint.h>

#include "board_config.h"
#if __has_include("generated/device_identity.h")
#include "generated/device_identity.h"
#endif

enum class NetworkMode : uint8_t {
  kAp = 0,
  kSta = 1,
  kApSta = 2,
};

namespace config {
#ifndef CONTROLLER_AP_SSID
#define CONTROLLER_AP_SSID "ESP32-Controller"
#endif
#ifndef CONTROLLER_BLE_NAME
#define CONTROLLER_BLE_NAME "ESP32 Web Gamepad"
#endif
#ifndef CONTROLLER_HOSTNAME
#define CONTROLLER_HOSTNAME "game"
#endif
#ifndef CONTROLLER_MDNS_INSTANCE_NAME
#define CONTROLLER_MDNS_INSTANCE_NAME "ESP32 Controller"
#endif
#ifndef CONTROLLER_DEVICE_UUID
#define CONTROLLER_DEVICE_UUID "00000000-0000-0000-0000-000000000000"
#endif
#ifndef CONTROLLER_FRIENDLY_NAME
#define CONTROLLER_FRIENDLY_NAME "ESP32 Controller"
#endif
#ifndef CONTROLLER_LOCAL_URL
#define CONTROLLER_LOCAL_URL "http://game.local"
#endif

static constexpr char kApSsid[] = CONTROLLER_AP_SSID;
static constexpr char kApPass[] = "";
static constexpr char kApHostname[] = CONTROLLER_HOSTNAME;
static constexpr NetworkMode kDefaultNetworkMode = NetworkMode::kApSta;
static constexpr uint16_t kHttpPort = 80;
static constexpr uint16_t kWsPort = 81;
static constexpr uint32_t kWsTimeoutMs = 500;
static constexpr uint32_t kStaConnectTimeoutMs = 15000;
static constexpr uint8_t kStaConnectMaxAttempts = 3;
static constexpr uint32_t kStaReconnectBackoffMs = 3000;
static constexpr uint32_t kStaCandidateStartDelayMs = 750;
static constexpr uint32_t kReportIntervalMs = 16;
static constexpr char kBleDeviceName[] = CONTROLLER_BLE_NAME;
static constexpr char kUsbSwitchProductName[] = CONTROLLER_FRIENDLY_NAME " Pad";
static constexpr char kMdnsInstanceName[] = CONTROLLER_MDNS_INSTANCE_NAME;
static constexpr char kFriendlyName[] = CONTROLLER_FRIENDLY_NAME;
static constexpr char kDeviceUuid[] = CONTROLLER_DEVICE_UUID;
static constexpr char kLocalUrl[] = CONTROLLER_LOCAL_URL;
static constexpr const char* kBoardName = board_config::kBoardName;
}  // namespace config
