#pragma once

// Centralized firmware-level constants for networking, timing, and BLE identity.

#include <stdint.h>

enum class NetworkMode : uint8_t {
  kAp = 0,
  kSta = 1,
  kApSta = 2,
};

namespace config {
static constexpr char kApSsid[] = "ESP32-Controller";
static constexpr char kApPass[] = "";
static constexpr char kApHostname[] = "game";
static constexpr NetworkMode kDefaultNetworkMode = NetworkMode::kApSta;
static constexpr uint16_t kHttpPort = 80;
static constexpr uint16_t kWsPort = 81;
static constexpr uint32_t kWsTimeoutMs = 500;
static constexpr uint32_t kStaConnectTimeoutMs = 15000;
static constexpr uint32_t kReportIntervalMs = 16;
static constexpr char kBleDeviceName[] = "ESP32 Web Gamepad";
static constexpr char kMdnsInstanceName[] = "ESP32 Controller";
}  // namespace config
