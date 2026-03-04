#include "network_manager.h"

#include <Arduino.h>
#include <string.h>

#include "config.h"

// TODO: move this into a helpers header or use STL
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

bool NetworkManager::begin() {
  return applyPreferredMode();
}

void NetworkManager::loop() {
  if (status_.mode == NetworkMode::kSta || status_.mode == NetworkMode::kApSta) {
    status_.sta_connected = WiFi.status() == WL_CONNECTED;
    if (status_.sta_connected) {
      status_.sta_ip = WiFi.localIP();
      return;
    }

    const uint32_t now = millis();
    if (sta_connect_started_ms_ > 0 && (now - sta_connect_started_ms_) > config::kStaConnectTimeoutMs) {
      // Fail-safe: keep AP available so phones can always reconnect to controller.
      status_.mode = NetworkMode::kApSta;
      WiFi.mode(WIFI_AP_STA);
      startAp();
      sta_connect_started_ms_ = 0;
    }
  }
}

bool NetworkManager::setStaCredentials(const char* ssid, const char* pass) {
  if (ssid == nullptr || strlen(ssid) == 0 || strlen(ssid) > 32) {
    return false;
  }
  copy_safe(status_.sta_ssid, sizeof(status_.sta_ssid), ssid);
  copy_safe(sta_pass_, sizeof(sta_pass_), pass == nullptr ? "" : pass);
  return true;
}

bool NetworkManager::connectSta() {
  if (strlen(status_.sta_ssid) == 0) {
    return false;
  }

  WiFi.mode(status_.mode == NetworkMode::kApSta ? WIFI_AP_STA : WIFI_STA);
  WiFi.begin(status_.sta_ssid, sta_pass_);
  sta_connect_started_ms_ = millis();
  return true;
}

void NetworkManager::startAp() {
  const bool ok = WiFi.softAP(config::kApSsid, config::kApPass);
  status_.ap_active = ok;
  if (ok) {
    status_.ap_ip = WiFi.softAPIP();
  }
}

NetworkStatus NetworkManager::status() const {
  return status_;
}

bool NetworkManager::applyPreferredMode() {
  status_.mode = config::kDefaultNetworkMode;

  switch (status_.mode) {
    case NetworkMode::kAp:
      WiFi.mode(WIFI_AP);
      startAp();
      return true;
    case NetworkMode::kSta:
      WiFi.mode(WIFI_STA);
      return connectSta();
    case NetworkMode::kApSta:
      WiFi.mode(WIFI_AP_STA);
      startAp();
      connectSta();
      return true;
  }

  return false;
}
