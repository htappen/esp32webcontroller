#include <Arduino.h>

#include <string.h>

#include "controller_session_manager.h"
#include "debug_log.h"
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
uint32_t g_last_loop_trace_ms = 0;
}

void setup() {
  debug_log::begin();
  delay(200);
  g_sessions.reset();
  g_network.begin();
  g_host.begin();
  g_sessions.setCapacity(strcmp(g_host.status().variant, "switch") == 0 ? 1 : config::kMaxControllerSlots);
  g_web.begin();
#if defined(CONTROLLER_BOARD_WROOM)
  debug_log::printf("ESP32 web BLE controller scaffold booted (%s)\n", config::kBoardName);
#elif defined(CONTROLLER_BOARD_S3)
  debug_log::printf("ESP32 web BLE controller scaffold booted (%s)\n", config::kBoardName);
#endif
  debug_log::printf("Device identity: uuid=%s name=%s hostname=%s local=%s\n", config::kDeviceUuid,
                    config::kFriendlyName, config::kApHostname, config::kLocalUrl);
}

void loop() {
  g_host.loop();
  g_web.loop();

  const uint32_t now = millis();
  if (now - g_last_report_ms >= config::kReportIntervalMs) {
    HostInputReport reports[config::kMaxControllerSlots] = {};
    const ControllerFleetSnapshot fleet = g_sessions.snapshot(now);
    debug_log::printf(now, &g_last_loop_trace_ms, config::kUsbSwitchTraceLogIntervalMs, false,
                      "[loop] report tick max=%u active=%u mask=0x%08lx\n", fleet.max_slots, fleet.active_slots,
                      static_cast<unsigned long>(fleet.active_slot_mask));
    for (uint8_t i = 0; i < fleet.max_slots; ++i) {
      if (fleet.slots[i].assigned) {
        reports[i] = InputMapper::map(fleet.slots[i].state);
      }
    }
    g_last_report_ms = now;
    g_host.sendSlotReports(reports, fleet.max_slots, fleet.active_slot_mask);
  }
}
