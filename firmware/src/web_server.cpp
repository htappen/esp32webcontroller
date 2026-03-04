#include "web_server.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <WebServer.h>

#include "config.h"

namespace {
WebServer g_http(config::kHttpPort);

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
}  // namespace

WebServerBridge::WebServerBridge(NetworkManager* network, HostConnectionManager* host, StateStore* state)
    : network_(network), host_(host), state_(state) {}

bool WebServerBridge::begin() {
  if (network_ == nullptr || host_ == nullptr || state_ == nullptr) {
    return false;
  }
  LittleFS.begin(true);

  g_http.on("/api/status", HTTP_GET, [this]() {
    JsonDocument doc;
    const NetworkStatus ns = network_->status();
    const HostStatus hs = host_->status();

    doc["network"]["mode"] = mode_to_string(ns.mode);
    doc["network"]["apActive"] = ns.ap_active;
    doc["network"]["staConnected"] = ns.sta_connected;
    doc["network"]["apIp"] = ns.ap_ip.toString();
    doc["network"]["staIp"] = ns.sta_ip.toString();
    doc["host"]["advertising"] = hs.advertising;
    doc["host"]["connected"] = hs.connected;

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
    g_http.send(200, "application/json", "{\"ok\":true}");
  });

  g_http.on("/api/host/pairing", HTTP_POST, [this]() {
    JsonDocument req;
    if (deserializeJson(req, g_http.arg("plain")) != DeserializationError::Ok) {
      g_http.send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }

    const bool enabled = req["enabled"] | true;
    host_->setPairingEnabled(enabled);
    g_http.send(200, "application/json", "{\"ok\":true}");
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
    if (g_http.uri().startsWith("/vendor/")) {
      File f = LittleFS.open(g_http.uri(), "r");
      if (!f) {
        g_http.send(404, "text/plain", "asset not found");
        return;
      }
      g_http.streamFile(f, "application/octet-stream");
      f.close();
      return;
    }
    g_http.send(404, "text/plain", "not found");
  });

  g_http.begin();

  // TODO: setup WebSocket server and route incoming messages via ws_parser_ into state_.
  return true;
}

void WebServerBridge::loop() {
  g_http.handleClient();
  // Keep manager state fresh even before server implementation lands.
  network_->loop();
  host_->loop();
  (void)state_;
}
