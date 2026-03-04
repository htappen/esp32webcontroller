#pragma once

#include "host_connection.h"
#include "network_manager.h"
#include "state_store.h"
#include "ws_bridge.h"

class WebServerBridge {
 public:
  WebServerBridge(NetworkManager* network, HostConnectionManager* host, StateStore* state);
  bool begin();
  void loop();

 private:
  NetworkManager* network_ = nullptr;
  HostConnectionManager* host_ = nullptr;
  StateStore* state_ = nullptr;
  WsBridge ws_parser_;
};
