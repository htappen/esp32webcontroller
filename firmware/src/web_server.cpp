#include "web_server.h"

#include <Arduino.h>
#include <ESPmDNS.h>
#include <LittleFS.h>
#include <WebServer.h>
#include <WebSocketsServer.h>

#include "config.h"

namespace {
WebServer g_http(config::kHttpPort);
WebSocketsServer g_ws(config::kWsPort);

const char* mode_to_string(NetworkMode mode) {
  switch (mode) {
    case NetworkMode::kAp:
      return "ap";
    case NetworkMode::kSta:
      return "sta";
    case NetworkMode::kApSta:
      return "apsta";
  }
  return "unknown";
}

const char* connection_state_to_string(NetworkConnectionState state) {
  switch (state) {
    case NetworkConnectionState::kNoSavedConfig:
      return "no_saved_config";
    case NetworkConnectionState::kApFallback:
      return "ap_fallback";
    case NetworkConnectionState::kStaConnecting:
      return "sta_connecting";
    case NetworkConnectionState::kStaConnected:
      return "sta_connected";
    case NetworkConnectionState::kStaCandidateFailed:
      return "sta_candidate_failed";
  }
  return "unknown";
}

const char* mime_type_for_path(const String& path) {
  if (path.endsWith(".js")) return "application/javascript";
  if (path.endsWith(".css")) return "text/css";
  if (path.endsWith(".svg")) return "image/svg+xml";
  if (path.endsWith(".html")) return "text/html";
  if (path.endsWith(".json")) return "application/json";
  return "application/octet-stream";
}

}  // namespace

WebServerBridge::WebServerBridge(NetworkManager* network, HostConnectionManager* host,
                                 ControllerSessionManager* sessions)
    : network_(network), host_(host), sessions_(sessions) {}

bool WebServerBridge::begin() {
  if (network_ == nullptr || host_ == nullptr || sessions_ == nullptr) {
    return false;
  }
  LittleFS.begin(true);
  syncMdns(network_->status());

  g_http.on("/api/status", HTTP_GET, [this]() {
    JsonDocument doc;
    const NetworkStatus ns = network_->status();
    const HostStatus hs = host_->status();
    const ControllerFleetSnapshot fleet = sessions_->snapshot(millis());

    doc["network"]["mode"] = mode_to_string(ns.mode);
    doc["network"]["connectionState"] = connection_state_to_string(ns.connection_state);
    doc["network"]["apActive"] = ns.ap_active;
    doc["network"]["apFallbackActive"] = ns.ap_fallback_active;
    doc["network"]["staConnected"] = ns.sta_connected;
    doc["network"]["staConnecting"] = ns.sta_connecting;
    doc["network"]["hasSavedStaConfig"] = ns.has_saved_sta_config;
    doc["network"]["candidateUpdateInProgress"] = ns.candidate_update_in_progress;
    doc["network"]["lastCandidateFailed"] = ns.last_candidate_failed;
    doc["network"]["apIp"] = ns.ap_ip.toString();
    doc["network"]["apSsid"] = config::kApSsid;
    doc["network"]["staIp"] = ns.sta_ip.toString();
    doc["network"]["activeStaSsid"] = ns.active_sta_ssid;
    doc["network"]["savedStaSsid"] = ns.saved_sta_ssid;
    doc["network"]["candidateStaSsid"] = ns.candidate_sta_ssid;
    doc["device"]["board"] = config::kBoardName;
    doc["device"]["uuid"] = config::kDeviceUuid;
    doc["device"]["friendlyName"] = config::kFriendlyName;
    doc["device"]["hostname"] = config::kApHostname;
    doc["device"]["hostnameLocal"] = config::kLocalUrl;
    doc["host"]["transport"] = hs.transport;
    doc["host"]["variant"] = hs.variant;
    doc["host"]["displayName"] = hs.display_name;
    doc["host"]["bleName"] = config::kBleDeviceName;
    doc["host"]["ready"] = hs.ready;
    doc["host"]["advertising"] = hs.advertising;
    doc["host"]["connected"] = hs.connected;
    doc["host"]["supportsPairing"] = hs.supports_pairing;
    doc["host"]["pairingEnabled"] = hs.pairing_enabled;
    doc["host"]["debug"]["usbInterfacesOpened"] = hs.usb_interfaces_opened;
    doc["host"]["debug"]["usbReportInFlight"] = hs.usb_report_in_flight;
    doc["host"]["debug"]["usbReportDirty"] = hs.usb_report_dirty;
    doc["host"]["debug"]["usbControlInEp"] = hs.usb_control_in_ep;
    doc["host"]["debug"]["usbSendAttempts"] = hs.usb_send_attempts;
    doc["host"]["debug"]["usbSendSuccesses"] = hs.usb_send_successes;
    doc["host"]["debug"]["usbInCompletions"] = hs.usb_in_completions;
    doc["host"]["debug"]["usbInFailures"] = hs.usb_in_failures;
    doc["host"]["debug"]["usbOutCompletions"] = hs.usb_out_completions;
    doc["controller"]["wsConnected"] = fleet.ws_connected;
    doc["controller"]["maxSlots"] = fleet.max_slots;
    doc["controller"]["assignedSlots"] = fleet.assigned_slots;
    doc["controller"]["activeSlots"] = fleet.active_slots;
    JsonArray clients = doc["controller"]["clients"].to<JsonArray>();
    for (uint8_t i = 0; i < fleet.max_slots; ++i) {
      const ControllerSlotSnapshot& slot = fleet.slots[i];
      JsonObject client = clients.add<JsonObject>();
      client["slot"] = slot.slot_number;
      client["assigned"] = slot.assigned;
      client["connected"] = slot.connected;
      client["reserved"] = slot.reserved;
      client["active"] = slot.active;
      client["lastPacketAgeMs"] = slot.last_packet_age_ms;
    }
    doc["controller"]["debug"]["wsPacketsReceived"] = ws_packets_received_;
    doc["controller"]["debug"]["wsPacketsApplied"] = ws_packets_applied_;
    doc["controller"]["debug"]["wsPacketsRejected"] = ws_packets_rejected_;

    String payload;
    serializeJson(doc, payload);
    g_http.send(200, "application/json", payload);
  });

  g_http.on("/api/network/sta", HTTP_POST, [this]() {
    JsonDocument req;
    if (deserializeJson(req, g_http.arg("plain")) != DeserializationError::Ok) {
      g_http.send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }

    const char* ssid = req["ssid"] | "";
    const char* pass = req["pass"] | "";
    if (!network_->setStaCredentials(ssid, pass)) {
      g_http.send(400, "application/json", "{\"error\":\"invalid_ssid\"}");
      return;
    }
    if (!network_->connectSta()) {
      g_http.send(500, "application/json", "{\"error\":\"sta_connect_failed\"}");
      return;
    }
    g_http.send(202, "application/json", "{\"ok\":true,\"status\":\"connecting\"}");
  });

  g_http.on("/api/host/forget", HTTP_POST, [this]() {
    if (!host_->forgetCurrentHost()) {
      g_http.send(409, "application/json", "{\"error\":\"host_reset_unavailable\"}");
      return;
    }
    g_http.send(200, "application/json", "{\"ok\":true,\"status\":\"host_forgotten\"}");
  });

  g_http.on("/api/host/pairing", HTTP_POST, [this]() {
    JsonDocument req;
    if (deserializeJson(req, g_http.arg("plain")) != DeserializationError::Ok ||
        !req["enabled"].is<bool>()) {
      g_http.send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }

    const bool enabled = req["enabled"].as<bool>();
    if (!host_->setPairingEnabled(enabled)) {
      g_http.send(409, "application/json", "{\"error\":\"pairing_control_unavailable\"}");
      return;
    }

    g_http.send(200, "application/json", enabled ? "{\"ok\":true,\"pairingEnabled\":true}"
                                                 : "{\"ok\":true,\"pairingEnabled\":false}");
  });

  g_http.on("/", HTTP_GET, []() {
    File f = LittleFS.open("/index.html", "r");
    if (!f) {
      g_http.send(404, "text/plain", "index.html not found");
      return;
    }
    g_http.streamFile(f, "text/html");
    f.close();
  });

  g_http.on("/app.js", HTTP_GET, []() {
    File f = LittleFS.open("/app.js", "r");
    if (!f) {
      g_http.send(404, "text/plain", "app.js not found");
      return;
    }
    g_http.streamFile(f, "application/javascript");
    f.close();
  });

  g_http.on("/app.css", HTTP_GET, []() {
    File f = LittleFS.open("/app.css", "r");
    if (!f) {
      g_http.send(404, "text/plain", "app.css not found");
      return;
    }
    g_http.streamFile(f, "text/css");
    f.close();
  });

  g_http.onNotFound([]() {
    File f = LittleFS.open(g_http.uri(), "r");
    if (!f) {
      g_http.send(404, "text/plain", "not found");
      return;
    }
    g_http.streamFile(f, mime_type_for_path(g_http.uri()));
    f.close();
  });

  g_http.begin();
  g_ws.begin();
  g_ws.onEvent([this](uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
    handleWsEvent(num, type, payload, length);
  });

  return true;
}

void WebServerBridge::loop() {
  g_http.handleClient();
  g_ws.loop();
  network_->loop();
  syncMdns(network_->status());
  const uint32_t now = millis();
  sessions_->evictExpiredReservations(now);

  uint8_t timed_out_clients[config::kMaxControllerSlots] = {};
  const uint8_t timed_out_count = sessions_->collectTimedOutClients(now, timed_out_clients, config::kMaxControllerSlots);
  for (uint8_t i = 0; i < timed_out_count && i < config::kMaxControllerSlots; ++i) {
    g_ws.disconnect(timed_out_clients[i]);
  }
}

void WebServerBridge::handleWsEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      break;
    case WStype_DISCONNECTED:
      sessions_->disconnectClient(num, millis());
      break;
    case WStype_TEXT: {
      if (payload == nullptr || length == 0) {
        return;
      }
      ++ws_packets_received_;
      String message;
      message.reserve(length + 1);
      for (size_t i = 0; i < length; ++i) {
        message += static_cast<char>(payload[i]);
      }

      const uint32_t now = millis();
      WsHelloPacket hello;
      if (ws_parser_.parseHello(message.c_str(), &hello)) {
        const ControllerBindOutcome outcome = sessions_->bindClient(num, hello.client_id, now);
        switch (outcome.result) {
          case ControllerBindResult::kAssigned:
            sendSessionMessage(num, true, outcome.slot_number, "assigned");
            if (outcome.previous_ws_client_num != 0xff && outcome.previous_ws_client_num != num) {
              g_ws.disconnect(outcome.previous_ws_client_num);
            }
            break;
          case ControllerBindResult::kReassigned:
            sendSessionMessage(num, true, outcome.slot_number, "reassigned");
            if (outcome.previous_ws_client_num != 0xff && outcome.previous_ws_client_num != num) {
              g_ws.disconnect(outcome.previous_ws_client_num);
            }
            break;
          case ControllerBindResult::kFull:
            sendSessionMessage(num, false, 0, "full");
            g_ws.disconnect(num);
            break;
          case ControllerBindResult::kInvalidClientId:
            sendSessionMessage(num, false, 0, "invalid_client_id");
            g_ws.disconnect(num);
            break;
        }
        return;
      }

      ControllerState base;
      if (!sessions_->getStateForClient(num, &base)) {
        ++ws_packets_rejected_;
        return;
      }

      ControllerState next;
      if (!ws_parser_.parseJson(message.c_str(), base, &next)) {
        ++ws_packets_rejected_;
        return;
      }
      next.last_update_ms = now;
      if (sessions_->applyStateForClient(num, next, now)) {
        ++ws_packets_applied_;
      } else {
        ++ws_packets_rejected_;
      }
      break;
    }
    case WStype_BIN:
    case WStype_PING:
    case WStype_PONG:
    case WStype_ERROR:
    case WStype_FRAGMENT_TEXT_START:
    case WStype_FRAGMENT_BIN_START:
    case WStype_FRAGMENT:
    case WStype_FRAGMENT_FIN:
      break;
  }
  (void)num;
}

void WebServerBridge::sendSessionMessage(uint8_t num, bool connected, uint8_t slot_number, const char* reason) {
  JsonDocument doc;
  doc["type"] = "session";
  doc["connected"] = connected;
  if (slot_number != 0) {
    doc["slot"] = slot_number;
  }
  doc["maxSlots"] = sessions_->capacity();
  doc["reason"] = reason;
  String payload;
  serializeJson(doc, payload);
  g_ws.sendTXT(num, payload);
}

void WebServerBridge::syncMdns(const NetworkStatus& status) {
  const IPAddress current_ip = status.sta_connected ? status.sta_ip : status.ap_ip;
  const bool reachable = status.sta_connected || status.ap_active;

  if (!reachable) {
    if (mdns_started_) {
      MDNS.end();
      mdns_started_ = false;
      mdns_ip_ = IPAddress();
    }
    return;
  }

  if (mdns_started_ && mdns_mode_ == status.mode && mdns_ip_ == current_ip) {
    return;
  }

  if (mdns_started_) {
    MDNS.end();
    mdns_started_ = false;
  }

  if (MDNS.begin(config::kApHostname)) {
    MDNS.setInstanceName(config::kMdnsInstanceName);
    MDNS.addService("http", "tcp", config::kHttpPort);
    MDNS.addService("ws", "tcp", config::kWsPort);
    mdns_started_ = true;
    mdns_mode_ = status.mode;
    mdns_ip_ = current_ip;
  } else {
    Serial.println("mDNS start failed");
  }
}
