#include "network_manager.h"

#include <Arduino.h>
#include <string.h>

#include "config.h"

NetworkManager::NetworkManager(DeviceSettingsStore* settings) : settings_(settings) {}

bool NetworkManager::begin() {
  if (settings_ != nullptr) {
    settings_->begin();
  }
  loadSavedCredentials();
  return applyPreferredMode();
}

void NetworkManager::loop() {
  const wl_status_t wifi_status = WiFi.status();
  const uint32_t now = millis();

  if (pending_candidate_connect_ && now >= pending_candidate_connect_at_ms_) {
    pending_candidate_connect_ = false;
    pending_candidate_connect_at_ms_ = 0;
    startStaAttempt(candidate_sta_, true);
    refreshRuntimeStatus();
    return;
  }

  if (status_.sta_connecting && wifi_status == WL_CONNECTED) {
    handleStaConnected();
    refreshRuntimeStatus();
    return;
  }

  if (status_.sta_connecting && sta_connect_started_ms_ > 0 &&
      (now - sta_connect_started_ms_) > config::kStaConnectTimeoutMs) {
    handleStaAttemptTimeout();
  } else if (!status_.sta_connecting && !status_.sta_connected && next_sta_retry_ms_ > 0 &&
             now >= next_sta_retry_ms_) {
    beginStaAttempt();
  }

  refreshRuntimeStatus();
}

bool NetworkManager::setStaCredentials(const char* ssid, const char* pass) {
  if (ssid == nullptr || strlen(ssid) == 0 || strlen(ssid) > 32) {
    return false;
  }
  candidate_sta_.present = true;
  copySafe(candidate_sta_.ssid, sizeof(candidate_sta_.ssid), ssid);
  copySafe(candidate_sta_.pass, sizeof(candidate_sta_.pass), pass == nullptr ? "" : pass);
  copySafe(status_.candidate_sta_ssid, sizeof(status_.candidate_sta_ssid), ssid);
  status_.last_candidate_failed = false;
  return true;
}

bool NetworkManager::connectSta() {
  if (!candidate_sta_.present || strlen(candidate_sta_.ssid) == 0) {
    return false;
  }
  pending_candidate_connect_ = true;
  pending_candidate_connect_at_ms_ = millis() + config::kStaCandidateStartDelayMs;
  status_.candidate_update_in_progress = true;
  status_.last_candidate_failed = false;
  status_.connection_state = NetworkConnectionState::kStaConnecting;
  return true;
}

void NetworkManager::startAp() {
  WiFi.softAPsetHostname(config::kApHostname);
  const bool ok = WiFi.softAP(config::kApSsid, config::kApPass);
  status_.ap_active = ok;
  if (ok) {
    status_.ap_ip = WiFi.softAPIP();
  }
}

void NetworkManager::stopAp() {
  WiFi.softAPdisconnect(true);
  status_.ap_active = false;
  status_.ap_ip = IPAddress();
}

NetworkStatus NetworkManager::status() const {
  return status_;
}

bool NetworkManager::applyPreferredMode() {
  if (committed_sta_.present) {
    return startStaAttempt(committed_sta_, false);
  }

  enterApFallback(false);
  status_.connection_state = NetworkConnectionState::kNoSavedConfig;
  return true;
}

bool NetworkManager::loadSavedCredentials() {
  committed_sta_ = StaCredentials{};
  if (settings_ == nullptr) {
    return false;
  }

  const DeviceStaSettings stored = settings_->loadStaSettings();
  committed_sta_.present = stored.has_credentials;
  if (!stored.has_credentials) {
    status_.has_saved_sta_config = false;
    status_.saved_sta_ssid[0] = '\0';
    return false;
  }

  copySafe(committed_sta_.ssid, sizeof(committed_sta_.ssid), stored.ssid);
  copySafe(committed_sta_.pass, sizeof(committed_sta_.pass), stored.pass);
  status_.has_saved_sta_config = true;
  copySafe(status_.saved_sta_ssid, sizeof(status_.saved_sta_ssid), stored.ssid);
  return true;
}

bool NetworkManager::startStaAttempt(const StaCredentials& creds, bool is_candidate) {
  if (!creds.present || strlen(creds.ssid) == 0) {
    return false;
  }

  active_attempt_is_candidate_ = is_candidate;
  sta_attempt_count_ = 0;
  next_sta_retry_ms_ = 0;
  pending_candidate_connect_ = false;
  pending_candidate_connect_at_ms_ = 0;
  status_.candidate_update_in_progress = is_candidate;
  status_.last_candidate_failed = false;
  copySafe(status_.active_sta_ssid, sizeof(status_.active_sta_ssid), creds.ssid);
  beginStaAttempt();
  return true;
}

void NetworkManager::beginStaAttempt() {
  const StaCredentials& attempt = active_attempt_is_candidate_ ? candidate_sta_ : committed_sta_;
  if (!attempt.present) {
    enterApFallback(active_attempt_is_candidate_);
    return;
  }

  ++sta_attempt_count_;
  stopAp();
  WiFi.disconnect(true, true);
  delay(100);
  WiFi.setAutoReconnect(false);
  WiFi.setHostname(config::kApHostname);
  WiFi.mode(WIFI_STA);
  WiFi.begin(attempt.ssid, attempt.pass);
  sta_connect_started_ms_ = millis();
  status_.mode = NetworkMode::kSta;
  status_.sta_connecting = true;
  status_.sta_connected = false;
  status_.ap_fallback_active = false;
  status_.connection_state = NetworkConnectionState::kStaConnecting;
}

void NetworkManager::handleStaConnected() {
  const StaCredentials& connected = active_attempt_is_candidate_ ? candidate_sta_ : committed_sta_;
  status_.sta_connecting = false;
  status_.sta_connected = true;
  sta_connect_started_ms_ = 0;
  next_sta_retry_ms_ = 0;
  status_.sta_ip = WiFi.localIP();
  status_.mode = NetworkMode::kSta;
  status_.ap_fallback_active = false;
  stopAp();

  if (active_attempt_is_candidate_) {
    if (settings_ != nullptr && settings_->saveStaSettings(connected.ssid, connected.pass)) {
      committed_sta_ = connected;
      status_.has_saved_sta_config = true;
      copySafe(status_.saved_sta_ssid, sizeof(status_.saved_sta_ssid), connected.ssid);
    }
    candidate_sta_ = StaCredentials{};
    status_.candidate_update_in_progress = false;
    status_.candidate_sta_ssid[0] = '\0';
  }

  copySafe(status_.active_sta_ssid, sizeof(status_.active_sta_ssid), connected.ssid);
  status_.connection_state = NetworkConnectionState::kStaConnected;
  active_attempt_is_candidate_ = false;
}

void NetworkManager::handleStaAttemptTimeout() {
  sta_connect_started_ms_ = 0;
  status_.sta_connecting = false;
  status_.sta_connected = false;
  status_.sta_ip = IPAddress();
  WiFi.disconnect(true, true);

  if (sta_attempt_count_ >= config::kStaConnectMaxAttempts) {
    enterApFallback(active_attempt_is_candidate_);
    return;
  }

  scheduleRetry();
}

void NetworkManager::enterApFallback(bool candidate_failed) {
  stopAp();
  WiFi.disconnect(true, true);
  WiFi.mode(WIFI_AP);
  startAp();
  status_.mode = NetworkMode::kAp;
  status_.sta_connecting = false;
  status_.sta_connected = false;
  status_.sta_ip = IPAddress();
  status_.ap_fallback_active = true;
  status_.candidate_update_in_progress = false;
  status_.connection_state = candidate_failed ? NetworkConnectionState::kStaCandidateFailed
                                              : (status_.has_saved_sta_config ? NetworkConnectionState::kApFallback
                                                                              : NetworkConnectionState::kNoSavedConfig);
  sta_connect_started_ms_ = 0;
  next_sta_retry_ms_ = 0;
  sta_attempt_count_ = 0;
  if (candidate_failed) {
    status_.last_candidate_failed = true;
    candidate_sta_ = StaCredentials{};
    status_.candidate_sta_ssid[0] = '\0';
  }
  active_attempt_is_candidate_ = false;
}

void NetworkManager::scheduleRetry() {
  next_sta_retry_ms_ = millis() + config::kStaReconnectBackoffMs;
  status_.sta_connecting = false;
  status_.sta_connected = false;
  status_.connection_state = NetworkConnectionState::kStaConnecting;
}

void NetworkManager::refreshRuntimeStatus() {
  const wl_status_t wifi_status = WiFi.status();
  if (!status_.sta_connecting) {
    status_.sta_connected = wifi_status == WL_CONNECTED;
  }

  if (status_.sta_connected) {
    status_.sta_ip = WiFi.localIP();
    if (strlen(status_.active_sta_ssid) == 0) {
      copySafe(status_.active_sta_ssid, sizeof(status_.active_sta_ssid), WiFi.SSID().c_str());
    }
    status_.mode = NetworkMode::kSta;
    status_.connection_state = NetworkConnectionState::kStaConnected;
    status_.ap_fallback_active = false;
  } else if (!status_.sta_connecting) {
    status_.sta_ip = IPAddress();
  }
}

void NetworkManager::copySafe(char* dst, size_t dst_size, const char* src) {
  if (dst == nullptr || dst_size == 0) {
    return;
  }
  dst[0] = '\0';
  if (src == nullptr) {
    return;
  }
  strlcpy(dst, src, dst_size);
}
