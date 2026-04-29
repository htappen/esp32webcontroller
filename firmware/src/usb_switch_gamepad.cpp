#include "usb_switch_gamepad.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)

#include <Arduino.h>
#include <USB.h>

#include <array>
#include <cstring>

#include "debug_log.h"
#include "config.h"
#include "esp32-hal-tinyusb.h"
#include "common/tusb_common.h"
#include "class/hid/hid.h"
#include "device/usbd.h"
#include "device/usbd_pvt.h"
#include "multi_controller_util.h"

namespace {
constexpr uint16_t kNintendoSwitchVid = 0x0f0d;
constexpr uint16_t kNintendoSwitchPid = 0x00c1;
constexpr uint8_t kHatUp = 0;
constexpr uint8_t kHatUpRight = 1;
constexpr uint8_t kHatRight = 2;
constexpr uint8_t kHatDownRight = 3;
constexpr uint8_t kHatDown = 4;
constexpr uint8_t kHatDownLeft = 5;
constexpr uint8_t kHatLeft = 6;
constexpr uint8_t kHatUpLeft = 7;
constexpr uint8_t kHatCentered = 0x0f;
constexpr uint8_t kTriggerButtonThreshold = 32;
constexpr uint8_t kEndpointPacketSize = 64;
constexpr uint8_t kEndpointIntervalMs = 5;
constexpr uint16_t kReportDescriptorLength = 80;
constexpr uint16_t kInterfaceDescriptorLength = TUD_HID_INOUT_DESC_LEN;
constexpr uint8_t kSwitchControllerCount = 1;

constexpr uint8_t kButtonY = 0;
constexpr uint8_t kButtonB = 1;
constexpr uint8_t kButtonA = 2;
constexpr uint8_t kButtonX = 3;
constexpr uint8_t kButtonL = 4;
constexpr uint8_t kButtonR = 5;
constexpr uint8_t kButtonZl = 6;
constexpr uint8_t kButtonZr = 7;
constexpr uint8_t kButtonMinus = 8;
constexpr uint8_t kButtonPlus = 9;
constexpr uint8_t kButtonLStick = 10;
constexpr uint8_t kButtonRStick = 11;

constexpr std::array<uint8_t, kReportDescriptorLength> kReportDescriptor = {
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x15, 0x00, 0x25, 0x01, 0x35, 0x00, 0x45, 0x01, 0x75,
    0x01, 0x95, 0x0E, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0E, 0x81, 0x02, 0x95, 0x02, 0x81, 0x01,
    0x05, 0x01, 0x25, 0x07, 0x46, 0x3B, 0x01, 0x75, 0x04, 0x95, 0x01, 0x65, 0x14, 0x09, 0x39,
    0x81, 0x42, 0x65, 0x00, 0x95, 0x01, 0x81, 0x01, 0x26, 0xFF, 0x00, 0x46, 0xFF, 0x00, 0x09,
    0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02, 0x75, 0x08,
    0x95, 0x01, 0x81, 0x01, 0xC0,
};

struct __attribute__((packed)) NintendoSwitchReport {
  uint16_t buttons = 0;
  uint8_t hat = kHatCentered;
  uint8_t left_x = 0x80;
  uint8_t left_y = 0x80;
  uint8_t right_x = 0x80;
  uint8_t right_y = 0x80;
  uint8_t reserved = 0;
};

struct SwitchSlotState {
  bool interfaces_opened = false;
  bool report_in_flight = false;
  bool report_dirty = false;
  bool has_queued_report = false;
  bool has_sent_non_neutral_report = false;
  bool host_out_seen = false;
  uint8_t rhport = 0;
  uint8_t interface_number = 0;
  uint8_t control_in_ep = 0;
  uint8_t control_out_ep = 0;
  uint8_t hid_instance = 0xff;
  uint8_t protocol = HID_PROTOCOL_REPORT;
  uint8_t idle_rate = 0;
  NintendoSwitchReport pending_report{};
  NintendoSwitchReport transfer_report{};
  NintendoSwitchReport last_queued_report{};
  alignas(4) uint8_t control_out_buffer[kEndpointPacketSize] = {};
};

std::array<uint8_t, kSwitchControllerCount * kInterfaceDescriptorLength> g_interface_descriptors = {};
SwitchSlotState g_slot_states[kSwitchControllerCount] = {};
bool g_descriptors_built = false;
uint8_t g_base_interface = 0;
bool g_started = false;
uint8_t g_active_slots = 0;
uint32_t g_send_attempt_count = 0;
uint32_t g_send_success_count = 0;

uint8_t axisToUint8(int16_t axis) {
  const int32_t shifted = static_cast<int32_t>(axis) + 32768;
  return static_cast<uint8_t>((shifted * 255) / 65535);
}

uint16_t buttonsFromReport(const HostInputReport& report) {
  uint16_t buttons = 0;
  if (report.btn.y) buttons |= (1u << kButtonY);
  if (report.btn.b) buttons |= (1u << kButtonB);
  if (report.btn.a) buttons |= (1u << kButtonA);
  if (report.btn.x) buttons |= (1u << kButtonX);
  if (report.btn.lb) buttons |= (1u << kButtonL);
  if (report.btn.rb) buttons |= (1u << kButtonR);
  if (report.lt >= kTriggerButtonThreshold) buttons |= (1u << kButtonZl);
  if (report.rt >= kTriggerButtonThreshold) buttons |= (1u << kButtonZr);
  if (report.btn.back) buttons |= (1u << kButtonMinus);
  if (report.btn.start) buttons |= (1u << kButtonPlus);
  if (report.btn.ls) buttons |= (1u << kButtonLStick);
  if (report.btn.rs) buttons |= (1u << kButtonRStick);
  return buttons;
}

uint8_t hatFromButtons(const Buttons& btn) {
  const bool up = btn.du;
  const bool down = btn.dd;
  const bool left = btn.dl;
  const bool right = btn.dr;

  if (up && right) return kHatUpRight;
  if (up && left) return kHatUpLeft;
  if (down && right) return kHatDownRight;
  if (down && left) return kHatDownLeft;
  if (up) return kHatUp;
  if (down) return kHatDown;
  if (right) return kHatRight;
  if (left) return kHatLeft;
  return kHatCentered;
}

NintendoSwitchReport reportFromHostInput(const HostInputReport& report) {
  NintendoSwitchReport switch_report;
  switch_report.buttons = buttonsFromReport(report);
  switch_report.hat = hatFromButtons(report.btn);
  switch_report.left_x = axisToUint8(report.lx);
  switch_report.left_y = axisToUint8(report.ly);
  switch_report.right_x = axisToUint8(report.rx);
  switch_report.right_y = axisToUint8(report.ry);
  switch_report.reserved = 0;
  return switch_report;
}

bool reportsEqual(const NintendoSwitchReport& lhs, const NintendoSwitchReport& rhs) {
  return memcmp(&lhs, &rhs, sizeof(lhs)) == 0;
}

bool reportIsNeutral(const NintendoSwitchReport& report) {
  return report.buttons == 0 && report.hat == kHatCentered && report.left_x == 0x80 && report.left_y == 0x80 &&
         report.right_x == 0x80 && report.right_y == 0x80;
}

bool slotCanTransfer(const SwitchSlotState& slot) {
  return slot.interfaces_opened && slot.control_in_ep != 0 && usbd_edpt_ready(slot.rhport, slot.control_in_ep);
}

void buildDescriptors(uint8_t base_interface) {
  if (g_descriptors_built) {
    return;
  }

  uint8_t* dst = g_interface_descriptors.data();
  const std::array<uint8_t, kInterfaceDescriptorLength> block = {
      TUD_HID_INOUT_DESCRIPTOR(base_interface, 0, 0, kReportDescriptorLength, 0x02, 0x81, kEndpointPacketSize,
                               kEndpointIntervalMs)};
  memcpy(dst, block.data(), block.size());
  g_descriptors_built = true;
}

void resetState() {
  memset(g_slot_states, 0, sizeof(g_slot_states));
  g_base_interface = 0;
  g_active_slots = 0;
  g_send_attempt_count = 0;
  g_send_success_count = 0;
}

bool startTransfer(uint8_t slot_index) {
  SwitchSlotState& slot = g_slot_states[slot_index];
  if (slot.report_in_flight || !tud_ready()) {
    return false;
  }

  if (!slotCanTransfer(slot)) {
    return false;
  }

  slot.transfer_report = slot.pending_report;
  const uint32_t now_ms = millis();
  static uint32_t last_start_trace_log_ms = 0;
  debug_log::printf(now_ms, &last_start_trace_log_ms, config::kUsbSwitchTraceLogIntervalMs, false,
                    "[host] usb_switch startTransfer slot=%u ep=0x%02x dirty=%u in_flight=%u\n",
                    static_cast<unsigned>(slot_index), static_cast<unsigned>(slot.control_in_ep),
                    slot.report_dirty ? 1u : 0u, slot.report_in_flight ? 1u : 0u);
  slot.report_in_flight = usbd_edpt_xfer(slot.rhport, slot.control_in_ep,
                                         reinterpret_cast<uint8_t*>(&slot.transfer_report),
                                         sizeof(slot.transfer_report));
  static uint32_t last_report_trace_log_ms = 0;
  debug_log::printf(now_ms, &last_report_trace_log_ms, config::kUsbSwitchTraceLogIntervalMs, false,
                    "[host] usb_switch report slot=%u ep=0x%02x in_flight=%u\n",
                    static_cast<unsigned>(slot_index), static_cast<unsigned>(slot.control_in_ep),
                    slot.report_in_flight ? 1u : 0u);
  if (slot.report_in_flight) {
    slot.report_dirty = false;
    slot.last_queued_report = slot.transfer_report;
    slot.has_queued_report = true;
    ++g_send_success_count;
    if (!reportIsNeutral(slot.transfer_report)) {
      slot.has_sent_non_neutral_report = true;
    }
  }
  return slot.report_in_flight;
}

int8_t slotIndexFromInterface(uint8_t interface_number) {
  return interface_number == g_base_interface ? 0 : -1;
}

int8_t slotIndexFromEndpoint(uint8_t ep_addr) {
  if (g_slot_states[0].interfaces_opened && g_slot_states[0].control_in_ep == ep_addr) {
    return 0;
  }
  return -1;
}

void switchDriverInit(void) {
  resetState();
}

void switchDriverReset(uint8_t rhport) {
  (void)rhport;
  resetState();
}

uint16_t switchDriverOpen(uint8_t rhport, tusb_desc_interface_t const* desc_intf, uint16_t max_len) {
  if (desc_intf->bInterfaceClass != TUSB_CLASS_HID) {
    return 0;
  }

  const int8_t slot_index = slotIndexFromInterface(desc_intf->bInterfaceNumber);
  if (slot_index < 0) {
    return 0;
  }

  SwitchSlotState& slot = g_slot_states[slot_index];
  slot = {};
  slot.interfaces_opened = true;
  slot.rhport = rhport;
  slot.interface_number = desc_intf->bInterfaceNumber;

  auto const* desc = reinterpret_cast<uint8_t const*>(desc_intf);
  uint16_t consumed = 0;
  while (consumed < max_len) {
    const uint8_t len = tu_desc_len(desc);
    if (len == 0 || consumed + len > max_len) {
      return 0;
    }
    if (consumed != 0 && tu_desc_type(desc) == TUSB_DESC_INTERFACE) {
      break;
    }
    if (tu_desc_type(desc) == TUSB_DESC_ENDPOINT) {
      auto const* ep_desc = reinterpret_cast<tusb_desc_endpoint_t const*>(desc);
      if (!usbd_edpt_open(rhport, ep_desc)) {
        slot.interfaces_opened = false;
        return 0;
      }
      if (tu_edpt_dir(ep_desc->bEndpointAddress) == TUSB_DIR_IN) {
        slot.control_in_ep = ep_desc->bEndpointAddress;
      } else {
        slot.control_out_ep = ep_desc->bEndpointAddress;
      }
    }
    consumed = static_cast<uint16_t>(consumed + len);
    desc = tu_desc_next(desc);
  }

  if (slot.control_out_ep != 0) {
    slot.host_out_seen = usbd_edpt_xfer(rhport, slot.control_out_ep, slot.control_out_buffer,
                                        sizeof(slot.control_out_buffer));
  }

  return consumed;
}

bool switchDriverControlXfer(uint8_t rhport, uint8_t stage, tusb_control_request_t const* request) {
  if (stage != CONTROL_STAGE_SETUP) {
    return true;
  }

  if (request->bmRequestType_bit.type == TUSB_REQ_TYPE_STANDARD && request->bRequest == TUSB_REQ_GET_DESCRIPTOR) {
    if (tu_u16_high(request->wValue) != HID_DESC_TYPE_REPORT) {
      return false;
    }
    const uint8_t interface_number = static_cast<uint8_t>(request->wIndex & 0xff);
    const int8_t slot_index = slotIndexFromInterface(interface_number);
    if (slot_index < 0) {
      return false;
    }
    return tud_control_xfer(rhport, request, const_cast<uint8_t*>(kReportDescriptor.data()),
                            kReportDescriptor.size());
  }

  if (request->bmRequestType_bit.type != TUSB_REQ_TYPE_CLASS) {
    return false;
  }

  const uint8_t interface_number = static_cast<uint8_t>(request->wIndex & 0xff);
  const int8_t slot_index = slotIndexFromInterface(interface_number);
  if (slot_index < 0) {
    return false;
  }

  switch (request->bRequest) {
    case HID_REQ_CONTROL_GET_REPORT:
      return tud_control_xfer(rhport, request, &g_slot_states[slot_index].pending_report,
                              sizeof(g_slot_states[slot_index].pending_report));
    case HID_REQ_CONTROL_GET_IDLE: {
      return tud_control_xfer(rhport, request, &g_slot_states[slot_index].idle_rate,
                              sizeof(g_slot_states[slot_index].idle_rate));
    }
    case HID_REQ_CONTROL_GET_PROTOCOL: {
      return tud_control_xfer(rhport, request, &g_slot_states[slot_index].protocol,
                              sizeof(g_slot_states[slot_index].protocol));
    }
    case HID_REQ_CONTROL_SET_REPORT:
    case HID_REQ_CONTROL_SET_IDLE:
    case HID_REQ_CONTROL_SET_PROTOCOL: {
      SwitchSlotState& slot = g_slot_states[slot_index];
      if (request->bRequest == HID_REQ_CONTROL_SET_IDLE) {
        slot.idle_rate = static_cast<uint8_t>(request->wValue >> 8);
      } else if (request->bRequest == HID_REQ_CONTROL_SET_PROTOCOL) {
        slot.protocol = static_cast<uint8_t>(request->wValue & 0xff);
      }
      return tud_control_status(rhport, request);
    }
    default:
      return false;
  }
}

bool switchDriverXfer(uint8_t rhport, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes) {
  (void)rhport;
  const int8_t slot_index = slotIndexFromEndpoint(ep_addr);
  if (slot_index < 0) {
    return false;
  }

  SwitchSlotState& slot = g_slot_states[slot_index];
  if (result != XFER_RESULT_SUCCESS) {
    slot.report_in_flight = false;
    if (ep_addr == slot.control_out_ep) {
      slot.host_out_seen = false;
    }
    return true;
  }

  if (ep_addr == slot.control_out_ep) {
    slot.host_out_seen = true;
    (void)xferred_bytes;
    slot.host_out_seen = usbd_edpt_xfer(slot.rhport, slot.control_out_ep, slot.control_out_buffer,
                                        sizeof(slot.control_out_buffer));
    return true;
  }

  slot.report_in_flight = false;
  if (slot.report_dirty) {
    (void)startTransfer(static_cast<uint8_t>(slot_index));
  }
  return true;
}

void switchDriverSof(uint8_t rhport, uint32_t frame_count) {
  (void)rhport;
  (void)frame_count;
  SwitchSlotState& slot = g_slot_states[0];
  if (slot.interfaces_opened && slot.report_dirty && !slot.report_in_flight) {
    (void)startTransfer(0);
  }
}

extern "C" usbd_class_driver_t const* usbd_app_driver_get_cb(uint8_t* driver_count) {
  static usbd_class_driver_t const kSwitchDriver = {
#if CFG_TUSB_DEBUG >= CFG_TUD_LOG_LEVEL
      "switch",
#endif
      switchDriverInit,
      switchDriverReset,
      switchDriverOpen,
      switchDriverControlXfer,
      switchDriverXfer,
      switchDriverSof,
  };

  *driver_count = 1;
  return &kSwitchDriver;
}

bool queueSlotReport(uint8_t slot_index, const NintendoSwitchReport& report) {
  SwitchSlotState& slot = g_slot_states[slot_index];
  if (reportIsNeutral(report) && !slot.has_sent_non_neutral_report) {
    slot.pending_report = report;
    slot.report_dirty = false;
    return true;
  }

  if (slot.report_in_flight && reportsEqual(report, slot.transfer_report)) {
    return true;
  }
  if (slot.report_dirty && reportsEqual(report, slot.pending_report)) {
    if (slot.report_in_flight) {
      return true;
    }
    return slotCanTransfer(slot) ? startTransfer(slot_index) : true;
  }
  if (!slot.report_in_flight && slot.has_queued_report && reportsEqual(report, slot.last_queued_report)) {
    return true;
  }

  slot.pending_report = report;
  slot.report_dirty = true;
  return slotCanTransfer(slot) ? startTransfer(slot_index) : true;
}

bool switchUsbInit() {
  static bool initialized = false;
  if (initialized) {
    return true;
  }

  if (tinyusb_enable_interface(USB_INTERFACE_CUSTOM, static_cast<uint16_t>(g_interface_descriptors.size()),
                               [](uint8_t* dst, uint8_t* itf) -> uint16_t {
                                 g_base_interface = *itf;
                                 buildDescriptors(*itf);
                                 memcpy(dst, g_interface_descriptors.data(), g_interface_descriptors.size());
                                 *itf = static_cast<uint8_t>(*itf + kSwitchControllerCount);
                                 return g_interface_descriptors.size();
                               }) != ESP_OK) {
    return false;
  }

  USB.VID(kNintendoSwitchVid);
  USB.PID(kNintendoSwitchPid);
  USB.usbClass(0);
  USB.usbSubClass(0);
  USB.usbProtocol(0);
  USB.productName("HORIPAD S");
  USB.manufacturerName("HORI CO.,LTD.");
  USB.serialNumber(config::kDeviceUuid);

  initialized = true;
  return true;
}
}  // namespace

bool UsbSwitchGamepadBridge::begin() {
  if (g_started) {
    return true;
  }
  resetState();
  if (!switchUsbInit()) {
    return false;
  }
  USB.begin();
  g_started = true;
  debug_log::printf("USB host ready: transport=usb variant=switch board=%s vid=%04x pid=%04x\n", config::kBoardName,
                    kNintendoSwitchVid, kNintendoSwitchPid);
  return true;
}

void UsbSwitchGamepadBridge::loop() {
  if (!g_started || !tud_ready()) {
    return;
  }
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    SwitchSlotState& slot = g_slot_states[i];
    if (slot.report_dirty && !slot.report_in_flight) {
      (void)startTransfer(i);
    }
  }
}

bool UsbSwitchGamepadBridge::resetConnection() {
  return false;
}

bool UsbSwitchGamepadBridge::setPairingEnabled(bool enabled) {
  (void)enabled;
  return false;
}

bool UsbSwitchGamepadBridge::send(const HostInputReport& report) {
  return sendSlots(&report, 1, 0x01);
}

bool UsbSwitchGamepadBridge::sendSlots(const HostInputReport* reports, uint8_t report_count, uint32_t active_slot_mask) {
  ++g_send_attempt_count;
  if (!g_started || reports == nullptr) {
    return false;
  }

  bool ok = true;
  g_active_slots = (report_count > 0 && (active_slot_mask & 0x01u) != 0) ? 1 : 0;
  const uint8_t capped_count = multi_controller::cappedReportCount(report_count);
  const uint32_t now_ms = millis();
  static uint32_t last_send_trace_log_ms = 0;
  debug_log::printf(now_ms, &last_send_trace_log_ms, config::kUsbSwitchTraceLogIntervalMs, false,
                    "[host] usb_switch sendSlots count=%u active=%lu capped=%u\n", report_count,
                    static_cast<unsigned long>(active_slot_mask), capped_count);
  const NintendoSwitchReport report =
      (capped_count > 0 && (active_slot_mask & 0x01u) != 0) ? reportFromHostInput(reports[0]) : NintendoSwitchReport{};
  ok = queueSlotReport(0, report) && ok;
  return ok;
}

HostStatus UsbSwitchGamepadBridge::status() const {
  HostStatus status;
  status.transport = "usb";
  status.variant = "switch";
  status.display_name = config::kUsbSwitchProductName;
  status.ready = g_started && tud_ready();
  status.connected = g_started && tud_mounted();
  status.supports_pairing = false;
  status.pairing_enabled = false;
  status.advertising = false;
  status.usb_active_slots = g_active_slots;
  status.usb_send_attempts = g_send_attempt_count;
  status.usb_send_successes = g_send_success_count;
  const SwitchSlotState& slot = g_slot_states[0];
  status.usb_interfaces_opened = slot.interfaces_opened;
  status.usb_report_in_flight = slot.report_in_flight;
  status.usb_report_dirty = slot.report_dirty;
  if (slot.control_in_ep != 0) {
    status.usb_control_in_ep = slot.control_in_ep;
  }
  return status;
}

#endif
