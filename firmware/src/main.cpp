#include <Arduino.h>

#include "config.h"
#include "host_connection.h"
#include "input_mapper.h"
#include "network_manager.h"
#include "state_store.h"
#include "web_server.h"

namespace {
StateStore g_state;
NetworkManager g_network;
HostConnectionManager g_host;
WebServerBridge g_web(&g_network, &g_host, &g_state);
uint32_t g_last_report_ms = 0;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  g_state.reset();
  g_network.begin();
  g_host.begin();
  g_web.begin();
  Serial.println("ESP32 web BLE controller scaffold booted");
}

void loop() {
  g_web.loop();

  const uint32_t now = millis();
  if (now - g_last_report_ms >= config::kReportIntervalMs) {
    g_last_report_ms = now;
    const ControllerState current = g_state.snapshot();
    const BleReport report = InputMapper::map(current);
    BleGamepadBridge* bridge = g_host.bridge();
    if (bridge != nullptr && bridge->connected()) {
      bridge->send(report);
    }
  }
}
