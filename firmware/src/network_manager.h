#pragma once

// Wi-Fi mode manager for AP/STA/AP+STA setup, credential handling, and status.

#include <WiFi.h>

#include <stdint.h>

#include "config.h"
#include "device_settings.h"

enum class NetworkConnectionState : uint8_t {
  kNoSavedConfig = 0,
  kApFallback = 1,
  kStaConnecting = 2,
  kStaConnected = 3,
  kStaCandidateFailed = 4,
};

struct NetworkStatus {
  NetworkMode mode = NetworkMode::kAp;
  bool ap_active = false;
  bool sta_connected = false;
  bool sta_connecting = false;
  bool has_saved_sta_config = false;
  bool ap_fallback_active = false;
  bool candidate_update_in_progress = false;
  bool last_candidate_failed = false;
  IPAddress ap_ip;
  IPAddress sta_ip;
  char active_sta_ssid[33] = {0};
  char saved_sta_ssid[33] = {0};
  char candidate_sta_ssid[33] = {0};
  NetworkConnectionState connection_state = NetworkConnectionState::kNoSavedConfig;
};

class NetworkManager {
 public:
  explicit NetworkManager(DeviceSettingsStore* settings);

  bool begin();
  void loop();

  bool setStaCredentials(const char* ssid, const char* pass);
  bool connectSta();
  void startAp();
  void stopAp();

  NetworkStatus status() const;

 private:
  struct StaCredentials {
    bool present = false;
    char ssid[33] = {0};
    char pass[65] = {0};
  };

  bool applyPreferredMode();
  bool loadSavedCredentials();
  bool startStaAttempt(const StaCredentials& creds, bool is_candidate);
  void beginStaAttempt();
  void handleStaConnected();
  void handleStaDisconnected();
  void handleStaAttemptTimeout();
  void enterApFallback(bool candidate_failed);
  void scheduleRetry();
  void refreshRuntimeStatus();
  static void copySafe(char* dst, size_t dst_size, const char* src);

  DeviceSettingsStore* settings_ = nullptr;
  NetworkStatus status_;
  StaCredentials committed_sta_;
  StaCredentials candidate_sta_;
  bool active_attempt_is_candidate_ = false;
  bool pending_candidate_connect_ = false;
  uint32_t pending_candidate_connect_at_ms_ = 0;
  uint8_t sta_attempt_count_ = 0;
  uint32_t sta_connect_started_ms_ = 0;
  uint32_t next_sta_retry_ms_ = 0;
};
