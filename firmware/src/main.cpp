#include <Arduino.h>

#include "config.h"
#include "device_settings.h"
#include "host_connection.h"
#include "input_mapper.h"
#include "network_manager.h"
#include "state_store.h"
#include "web_server.h"

namespace {
StateStore g_state;
DeviceSettingsStore g_settings;
NetworkManager g_network(&g_settings);
HostConnectionManager g_host(&g_settings);
WebServerBridge g_web(&g_network, &g_host, &g_state);
uint32_t g_last_report_ms = 0;
bool g_last_host_connected = false;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  g_state.reset();
  g_network.begin();
  g_host.begin();
  g_web.begin();
#if defined(CONTROLLER_BOARD_WROOM)
  Serial.printf("ESP32 web BLE controller scaffold booted (%s)\n", config::kBoardName);
#elif defined(CONTROLLER_BOARD_S3)
  Serial.printf("ESP32 web BLE controller scaffold booted (%s)\n", config::kBoardName);
#endif
  Serial.printf("Device identity: uuid=%s name=%s hostname=%s local=%s\n", config::kDeviceUuid,
                config::kFriendlyName, config::kApHostname, config::kLocalUrl);
}

void loop() {
  g_host.loop();
  g_web.loop();

  const HostStatus host_status = g_host.status();
  if (g_last_host_connected && !host_status.connected) {
    g_state.reset();
  }
  g_last_host_connected = host_status.connected;

  const uint32_t now = millis();
  if (now - g_last_report_ms >= config::kReportIntervalMs) {
    g_last_report_ms = now;
    g_host.sendReport(InputMapper::map(g_state.snapshot()));
  }
}
