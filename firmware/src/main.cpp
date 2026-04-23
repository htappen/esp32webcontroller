#include <Arduino.h>

#include <string.h>

#include "controller_session_manager.h"
#include "config.h"
#include "device_settings.h"
#include "host_connection.h"
#include "input_mapper.h"
#include "network_manager.h"
#include "web_server.h"

namespace {
ControllerSessionManager g_sessions;
DeviceSettingsStore g_settings;
NetworkManager g_network(&g_settings);
HostConnectionManager g_host(&g_settings);
WebServerBridge g_web(&g_network, &g_host, &g_sessions);
uint32_t g_last_report_ms = 0;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  g_sessions.reset();
  g_network.begin();
  g_host.begin();
  g_sessions.setCapacity(strcmp(g_host.status().transport, "usb") == 0 ? config::kMaxControllerSlots : 1);
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

  const uint32_t now = millis();
  if (now - g_last_report_ms >= config::kReportIntervalMs) {
    HostInputReport reports[config::kMaxControllerSlots] = {};
    const ControllerFleetSnapshot fleet = g_sessions.snapshot(now);
    for (uint8_t i = 0; i < fleet.max_slots; ++i) {
      if (fleet.slots[i].assigned) {
        reports[i] = InputMapper::map(fleet.slots[i].state);
      }
    }
    g_last_report_ms = now;
    g_host.sendSlotReports(reports, fleet.max_slots, fleet.active_slot_mask);
  }
}
