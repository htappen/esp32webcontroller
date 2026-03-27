#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct DeviceStaSettings {
  bool has_credentials = false;
  char ssid[33] = {0};
  char pass[65] = {0};
};

struct DeviceRuntimeSettings {
  bool pairing_enabled = true;
};

class DeviceSettingsStore {
 public:
  bool begin();
  DeviceStaSettings loadStaSettings() const;
  bool saveStaSettings(const char* ssid, const char* pass);
  bool clearStaSettings();
  DeviceRuntimeSettings loadRuntimeSettings() const;
  bool saveRuntimeSettings(const DeviceRuntimeSettings& settings);

 private:
  static constexpr const char* kNamespace = "controller";
  static constexpr const char* kSchemaVersionKey = "schema";
  static constexpr const char* kStaSsidKey = "sta_ssid";
  static constexpr const char* kStaPassKey = "sta_pass";
  static constexpr const char* kPairingEnabledKey = "pairing_on";
  static constexpr uint32_t kSchemaVersion = 1;
  bool ready_ = false;
};
