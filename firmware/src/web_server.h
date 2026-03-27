#pragma once

// HTTP and WebSocket front-end bridge for status APIs, control APIs, and input ingest.

#include "host_connection.h"
#include "network_manager.h"
#include "state_store.h"
#include "ws_bridge.h"
#include <WebSocketsServer.h>

class WebServerBridge {
 public:
  WebServerBridge(NetworkManager* network, HostConnectionManager* host, StateStore* state);
  bool begin();
  void loop();

 private:
  void handleWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length);
  void resetControllerState();
  void sendNeutralReport();
  void syncMdns(const NetworkStatus& status);

  NetworkManager* network_ = nullptr;
  HostConnectionManager* host_ = nullptr;
  StateStore* state_ = nullptr;
  WsBridge ws_parser_;
  bool ws_client_connected_ = false;
  uint32_t ws_last_packet_ms_ = 0;
  uint32_t ws_packets_received_ = 0;
  uint32_t ws_packets_applied_ = 0;
  uint32_t ws_packets_rejected_ = 0;
  bool mdns_started_ = false;
  NetworkMode mdns_mode_ = NetworkMode::kAp;
  IPAddress mdns_ip_;
};
