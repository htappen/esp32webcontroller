#pragma once

// Wi-Fi mode manager for AP/STA/AP+STA setup, credential handling, and status.

#include <WiFi.h>

#include <stdint.h>

#include "config.h"

struct NetworkStatus {
  NetworkMode mode = NetworkMode::kAp;
  bool ap_active = false;
  bool sta_connected = false;
  IPAddress ap_ip;
  IPAddress sta_ip;
  char sta_ssid[33] = {0};
};

class NetworkManager {
 public:
  bool begin();
  void loop();

  bool setStaCredentials(const char* ssid, const char* pass);
  bool connectSta();
  void startAp();

  NetworkStatus status() const;

 private:
  bool applyPreferredMode();

  NetworkStatus status_;
  char sta_pass_[65] = {0};
  uint32_t sta_connect_started_ms_ = 0;
};
