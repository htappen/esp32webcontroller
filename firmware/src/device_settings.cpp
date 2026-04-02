#include "device_settings.h"

#include <Preferences.h>
#include <string.h>

#include "config.h"

namespace {
void copy_safe(char* dst, size_t dst_size, const char* src) {
  if (dst == nullptr || dst_size == 0) {
    return;
  }
  dst[0] = '\0';
  if (src == nullptr) {
    return;
  }
  strlcpy(dst, src, dst_size);
}
}  // namespace

bool DeviceSettingsStore::begin() {
  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    ready_ = false;
    return false;
  }

  const uint32_t schema = prefs.getUInt(kSchemaVersionKey, 0);
  if (schema != kSchemaVersion) {
    prefs.clear();
    prefs.putUInt(kSchemaVersionKey, kSchemaVersion);
  }
  seedDefaultStaSettings(&prefs);
  prefs.end();
  ready_ = true;
  return true;
}

bool DeviceSettingsStore::seedDefaultStaSettings(Preferences* prefs) const {
  if (prefs == nullptr || prefs->isKey(kStaSsidKey)) {
    return false;
  }
  if (strlen(config::kDefaultStaSsid) == 0) {
    return false;
  }

  return prefs->putString(kStaSsidKey, config::kDefaultStaSsid) > 0 &&
         prefs->putString(kStaPassKey, config::kDefaultStaPass) >= 0;
}

DeviceStaSettings DeviceSettingsStore::loadStaSettings() const {
  DeviceStaSettings settings;
  if (!ready_) {
    return settings;
  }

  Preferences prefs;
  if (!prefs.begin(kNamespace, true)) {
    return settings;
  }

  if (!prefs.isKey(kStaSsidKey)) {
    prefs.end();
    return settings;
  }

  const String ssid = prefs.getString(kStaSsidKey, "");
  const String pass = prefs.isKey(kStaPassKey) ? prefs.getString(kStaPassKey, "") : "";
  prefs.end();

  if (!ssid.isEmpty()) {
    settings.has_credentials = true;
    copy_safe(settings.ssid, sizeof(settings.ssid), ssid.c_str());
    copy_safe(settings.pass, sizeof(settings.pass), pass.c_str());
  }
  return settings;
}

bool DeviceSettingsStore::saveStaSettings(const char* ssid, const char* pass) {
  if (!ready_ || ssid == nullptr || strlen(ssid) == 0) {
    return false;
  }

  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  prefs.putUInt(kSchemaVersionKey, kSchemaVersion);
  const bool ok = prefs.putString(kStaSsidKey, ssid) > 0 &&
                  prefs.putString(kStaPassKey, pass == nullptr ? "" : pass) >= 0;
  prefs.end();
  return ok;
}

bool DeviceSettingsStore::clearStaSettings() {
  if (!ready_) {
    return false;
  }

  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  prefs.remove(kStaSsidKey);
  prefs.remove(kStaPassKey);
  prefs.putUInt(kSchemaVersionKey, kSchemaVersion);
  prefs.end();
  return true;
}

DeviceRuntimeSettings DeviceSettingsStore::loadRuntimeSettings() const {
  DeviceRuntimeSettings settings;
  if (!ready_) {
    return settings;
  }

  Preferences prefs;
  if (!prefs.begin(kNamespace, true)) {
    return settings;
  }

  settings.pairing_enabled = prefs.getBool(kPairingEnabledKey, true);
  prefs.end();
  return settings;
}

bool DeviceSettingsStore::saveRuntimeSettings(const DeviceRuntimeSettings& settings) {
  if (!ready_) {
    return false;
  }

  Preferences prefs;
  if (!prefs.begin(kNamespace, false)) {
    return false;
  }

  prefs.putUInt(kSchemaVersionKey, kSchemaVersion);
  const bool ok = prefs.putBool(kPairingEnabledKey, settings.pairing_enabled);
  prefs.end();
  return ok;
}
