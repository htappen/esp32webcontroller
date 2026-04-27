#include "host_connection.h"

#include <Arduino.h>

#include "ble_gamepad.h"
#include "debug_log.h"
#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)
#include "usb_xinput_gamepad.h"
#endif
#if defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)
#include "usb_switch_gamepad.h"
#endif

namespace {
#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)
UsbXInputGamepadBridge g_usb_xinput_transport;
#elif defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)
UsbSwitchGamepadBridge g_usb_switch_transport;
#else
BleGamepadBridge g_ble_transport;
#endif
}  // namespace

HostConnectionManager::HostConnectionManager(DeviceSettingsStore* settings) : settings_(settings) {
#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)
  transport_ = &g_usb_xinput_transport;
#elif defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)
  transport_ = &g_usb_switch_transport;
#else
  transport_ = &g_ble_transport;
#endif
}

bool HostConnectionManager::begin() {
  if (transport_ == nullptr) {
    return false;
  }
  if (settings_ != nullptr) {
    const DeviceRuntimeSettings runtime = settings_->loadRuntimeSettings();
    pairing_enabled_ = runtime.pairing_enabled;
  }
  if (!transport_->begin()) {
    return false;
  }
  transport_->setPairingEnabled(pairing_enabled_);
  refreshStatus();
  return true;
}

void HostConnectionManager::loop() {
  if (transport_ == nullptr) {
    return;
  }
  transport_->loop();
  refreshStatus();
}

bool HostConnectionManager::forgetCurrentHost() {
  if (transport_ == nullptr || !status_.supports_pairing) {
    return false;
  }
  const bool forgotten = transport_->resetConnection();
  refreshStatus();
  return forgotten;
}

bool HostConnectionManager::setPairingEnabled(bool enabled) {
  if (transport_ == nullptr || !status_.supports_pairing) {
    return false;
  }
  const bool previous = pairing_enabled_;
  bool saved = true;
  if (settings_ != nullptr) {
    DeviceRuntimeSettings runtime;
    runtime.pairing_enabled = enabled;
    saved = settings_->saveRuntimeSettings(runtime);
  }

  if (!saved) {
    pairing_enabled_ = previous;
    transport_->setPairingEnabled(previous);
    refreshStatus();
    return false;
  }

  pairing_enabled_ = enabled;
  transport_->setPairingEnabled(enabled);
  refreshStatus();
  return saved;
}

bool HostConnectionManager::sendReport(const HostInputReport& report) {
  if (transport_ == nullptr) {
    return false;
  }
  const bool ok = transport_->send(report);
  if (!ok) {
    debug_log::printf("[host] sendReport failed transport=%s variant=%s\n", status_.transport, status_.variant);
  }
  return ok;
}

bool HostConnectionManager::sendSlotReports(const HostInputReport* reports, uint8_t report_count,
                                            uint32_t active_slot_mask) {
  if (transport_ == nullptr) {
    return false;
  }
  const bool ok = transport_->sendSlots(reports, report_count, active_slot_mask);
  if (!ok) {
    debug_log::printf("[host] sendSlotReports failed transport=%s variant=%s count=%u mask=0x%08lx\n",
                      status_.transport, status_.variant, report_count,
                      static_cast<unsigned long>(active_slot_mask));
  }
  return ok;
}

HostStatus HostConnectionManager::status() const {
  return status_;
}

void HostConnectionManager::refreshStatus() {
  if (transport_ == nullptr) {
    status_ = HostStatus{};
    status_.ready = false;
    return;
  }
  status_ = transport_->status();
  if (status_.supports_pairing) {
    status_.pairing_enabled = pairing_enabled_;
  }
}
