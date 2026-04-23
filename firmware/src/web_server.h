#pragma once

// HTTP and WebSocket front-end bridge for status APIs, control APIs, and input ingest.

#include "controller_session_manager.h"
#include "host_connection.h"
#include "network_manager.h"
#include "ws_bridge.h"
#include <WebSocketsServer.h>

class WebServerBridge {
 public:
  WebServerBridge(NetworkManager* network, HostConnectionManager* host, ControllerSessionManager* sessions);
  bool begin();
  void loop();

 private:
  void handleWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length);
  void sendSessionMessage(uint8_t num, bool connected, uint8_t slot_number, const char* reason);
  void syncMdns(const NetworkStatus& status);

  NetworkManager* network_ = nullptr;
  HostConnectionManager* host_ = nullptr;
  ControllerSessionManager* sessions_ = nullptr;
  WsBridge ws_parser_;
  uint32_t ws_packets_received_ = 0;
  uint32_t ws_packets_applied_ = 0;
  uint32_t ws_packets_rejected_ = 0;
  bool mdns_started_ = false;
  NetworkMode mdns_mode_ = NetworkMode::kAp;
  IPAddress mdns_ip_;
};
