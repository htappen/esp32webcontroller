#pragma once

#include <stdint.h>

#include "input_mapper.h"

struct HostStatus {
  const char* transport = "ble";
  const char* variant = "default";
  const char* display_name = "";
  bool ready = false;
  bool connected = false;
  bool supports_pairing = false;
  bool pairing_enabled = false;
  bool advertising = false;
  bool usb_interfaces_opened = false;
  bool usb_report_in_flight = false;
  bool usb_report_dirty = false;
  uint8_t usb_control_in_ep = 0;
  uint8_t usb_active_slots = 0;
  uint32_t usb_send_attempts = 0;
  uint32_t usb_send_successes = 0;
  uint32_t usb_in_completions = 0;
  uint32_t usb_in_failures = 0;
  uint32_t usb_out_completions = 0;
};

class HostTransport {
 public:
  virtual ~HostTransport() = default;

  virtual bool begin() = 0;
  virtual void loop() = 0;
  virtual bool resetConnection() = 0;
  virtual bool setPairingEnabled(bool enabled) = 0;
  virtual bool send(const HostInputReport& report) = 0;
  virtual bool sendSlots(const HostInputReport* reports, uint8_t report_count, uint32_t active_slot_mask) {
    if (reports == nullptr || report_count == 0) {
      return send(HostInputReport{});
    }
    for (uint8_t i = 0; i < report_count; ++i) {
      if ((active_slot_mask & (1u << i)) != 0) {
        return send(reports[i]);
      }
    }
    return send(HostInputReport{});
  }
  virtual HostStatus status() const = 0;
};
