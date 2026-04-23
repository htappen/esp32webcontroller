#include "usb_xinput_gamepad.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)

#include <Arduino.h>
#include <USB.h>

#include <array>
#include <cstring>

#include "common/tusb_common.h"
#include "common/tusb_types.h"
#include "config.h"
#include "device/usbd.h"
#include "device/usbd_pvt.h"
#include "esp32-hal-tinyusb.h"
#include "esp_rom_sys.h"

namespace {
constexpr uint16_t kXbox360Vid = 0x045e;
constexpr uint16_t kXbox360Pid = 0x028e;
constexpr uint8_t kVendorClass = 0xff;
constexpr uint8_t kXInputSubClass = 0x5d;
constexpr uint8_t kXInputProtocol = 0x01;
constexpr uint8_t kEndpointPacketSize = 32;
constexpr uint8_t kEndpointZeroPacketSize = CFG_TUD_ENDPOINT0_SIZE;
constexpr uint16_t kXbox360BcdDevice = 0x0114;
constexpr uint8_t kManufacturerStringIndex = 0x01;
constexpr uint8_t kProductStringIndex = 0x02;
constexpr uint8_t kSerialStringIndex = 0x03;
constexpr uint8_t kLanguageStringIndex = 0x00;
constexpr uint8_t kDescriptorInterfaceLength = 40;
constexpr uint16_t kConfigurationTotalLength =
    TUD_CONFIG_DESC_LEN + (config::kMaxControllerSlots * kDescriptorInterfaceLength);

constexpr uint8_t kButtonDu = 0;
constexpr uint8_t kButtonDd = 1;
constexpr uint8_t kButtonDl = 2;
constexpr uint8_t kButtonDr = 3;
constexpr uint8_t kButtonStart = 4;
constexpr uint8_t kButtonBack = 5;
constexpr uint8_t kButtonLs = 6;
constexpr uint8_t kButtonRs = 7;
constexpr uint8_t kButtonLb = 8;
constexpr uint8_t kButtonRb = 9;
constexpr uint8_t kButtonA = 12;
constexpr uint8_t kButtonB = 13;
constexpr uint8_t kButtonX = 14;
constexpr uint8_t kButtonY = 15;

struct __attribute__((packed)) XInputControlReport {
  uint8_t type = 0x00;
  uint8_t size = 20;
  uint16_t buttons = 0;
  uint8_t lt = 0;
  uint8_t rt = 0;
  int16_t lx = 0;
  int16_t ly = 0;
  int16_t rx = 0;
  int16_t ry = 0;
  uint8_t reserved[6] = {};
};

static_assert(sizeof(XInputControlReport) == 20);

struct XInputSlotState {
  bool interfaces_opened = false;
  bool report_in_flight = false;
  bool report_dirty = false;
  bool host_out_seen = false;
  bool has_sent_non_neutral_report = false;
  bool has_queued_report = false;
  uint8_t rhport = 0;
  uint8_t interface_number = 0;
  uint8_t control_in_ep = 0;
  uint8_t control_out_ep = 0;
  XInputControlReport pending_report;
  XInputControlReport transfer_report;
  XInputControlReport last_queued_report;
  alignas(4) uint8_t control_out_buffer[kEndpointPacketSize] = {};
};

std::array<uint8_t, config::kMaxControllerSlots * kDescriptorInterfaceLength> g_interface_descriptors = {};
std::array<uint8_t, kConfigurationTotalLength> g_configuration_descriptor = {};
std::array<XInputSlotState, config::kMaxControllerSlots> g_slot_states = {};
bool g_descriptors_built = false;
bool g_logged_custom_descriptor = false;
bool g_logged_device_descriptor = false;
bool g_logged_config_descriptor = false;
bool g_logged_string_descriptor[4] = {};
uint32_t g_send_attempt_count = 0;
uint32_t g_send_success_count = 0;
uint32_t g_in_xfer_complete_count = 0;
uint32_t g_in_xfer_failure_count = 0;
uint32_t g_out_xfer_complete_count = 0;
uint8_t g_active_slots = 0;

constexpr std::array<uint8_t, 8> kCapabilitiesFeedback = {
    0x00, 0x08, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00,
};

constexpr std::array<uint8_t, 20> kCapabilitiesInputs = {
    0x00, 0x14, 0x3f, 0xf7, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
    0xc0, 0xff, 0xc0, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

constexpr tusb_desc_device_t kXbox360DeviceDescriptor = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bDeviceClass = kVendorClass,
    .bDeviceSubClass = kVendorClass,
    .bDeviceProtocol = kVendorClass,
    .bMaxPacketSize0 = kEndpointZeroPacketSize,
    .idVendor = kXbox360Vid,
    .idProduct = kXbox360Pid,
    .bcdDevice = kXbox360BcdDevice,
    .iManufacturer = kManufacturerStringIndex,
    .iProduct = kProductStringIndex,
    .iSerialNumber = kSerialStringIndex,
    .bNumConfigurations = 0x01,
};

void buildDescriptors() {
  if (g_descriptors_built) {
    return;
  }

  g_configuration_descriptor = {
      0x09,
      0x02,
      static_cast<uint8_t>(kConfigurationTotalLength & 0xff),
      static_cast<uint8_t>((kConfigurationTotalLength >> 8) & 0xff),
      config::kMaxControllerSlots,
      0x01,
      0x00,
      0xA0,
      0xFA,
  };

  for (uint8_t slot = 0; slot < config::kMaxControllerSlots; ++slot) {
    const uint8_t in_ep = static_cast<uint8_t>(0x81 + slot);
    const uint8_t out_ep = static_cast<uint8_t>(0x01 + slot);
    const size_t offset = slot * kDescriptorInterfaceLength;
    const std::array<uint8_t, kDescriptorInterfaceLength> block = {
        0x09, 0x04, slot, 0x00, 0x02, kVendorClass, kXInputSubClass, kXInputProtocol, 0x00,
        0x11, 0x21, 0x00, 0x01, 0x01, 0x25, in_ep, 0x14, 0x00, 0x00, 0x00, 0x00, 0x13, 0x01, 0x08, 0x00, 0x00,
        0x07, 0x05, in_ep, 0x03, 0x20, 0x00, 0x04,
        0x07, 0x05, out_ep, 0x03, 0x20, 0x00, 0x08,
    };
    memcpy(g_interface_descriptors.data() + offset, block.data(), block.size());
    memcpy(g_configuration_descriptor.data() + TUD_CONFIG_DESC_LEN + offset, block.data(), block.size());
  }

  g_descriptors_built = true;
}

uint32_t serialFromUuid() {
  uint32_t hash = 2166136261u;
  for (const char* p = config::kDeviceUuid; *p != '\0'; ++p) {
    hash ^= static_cast<uint8_t>(*p);
    hash *= 16777619u;
  }
  return hash;
}

std::array<uint8_t, 4> serialPacket() {
  const uint32_t value = serialFromUuid();
  return {
      static_cast<uint8_t>((value >> 24) & 0xff),
      static_cast<uint8_t>((value >> 16) & 0xff),
      static_cast<uint8_t>((value >> 8) & 0xff),
      static_cast<uint8_t>(value & 0xff),
  };
}

uint16_t buttonsFromReport(const HostInputReport& report) {
  uint16_t buttons = 0;
  if (report.btn.du) buttons |= (1u << kButtonDu);
  if (report.btn.dd) buttons |= (1u << kButtonDd);
  if (report.btn.dl) buttons |= (1u << kButtonDl);
  if (report.btn.dr) buttons |= (1u << kButtonDr);
  if (report.btn.start) buttons |= (1u << kButtonStart);
  if (report.btn.back) buttons |= (1u << kButtonBack);
  if (report.btn.ls) buttons |= (1u << kButtonLs);
  if (report.btn.rs) buttons |= (1u << kButtonRs);
  if (report.btn.lb) buttons |= (1u << kButtonLb);
  if (report.btn.rb) buttons |= (1u << kButtonRb);
  if (report.btn.a) buttons |= (1u << kButtonA);
  if (report.btn.b) buttons |= (1u << kButtonB);
  if (report.btn.x) buttons |= (1u << kButtonX);
  if (report.btn.y) buttons |= (1u << kButtonY);
  return buttons;
}

XInputControlReport reportFromHostInput(const HostInputReport& report) {
  XInputControlReport xinput_report;
  xinput_report.buttons = buttonsFromReport(report);
  xinput_report.lt = report.lt;
  xinput_report.rt = report.rt;
  xinput_report.lx = report.lx;
  xinput_report.ly = report.ly;
  xinput_report.rx = report.rx;
  xinput_report.ry = report.ry;
  return xinput_report;
}

bool xinputReportIsNeutral(const XInputControlReport& report) {
  return report.buttons == 0 && report.lt == 0 && report.rt == 0 && report.lx == 0 && report.ly == 0 &&
         report.rx == 0 && report.ry == 0;
}

bool xinputReportsEqual(const XInputControlReport& lhs, const XInputControlReport& rhs) {
  return memcmp(&lhs, &rhs, sizeof(lhs)) == 0;
}

int8_t slotIndexFromInterface(uint8_t interface_number) {
  return interface_number < config::kMaxControllerSlots ? static_cast<int8_t>(interface_number) : -1;
}

int8_t slotIndexFromEndpoint(uint8_t ep_addr) {
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    if (!g_slot_states[i].interfaces_opened) {
      continue;
    }
    if (g_slot_states[i].control_in_ep == ep_addr || g_slot_states[i].control_out_ep == ep_addr) {
      return static_cast<int8_t>(i);
    }
  }
  return -1;
}

bool xinputPrimeOutEndpoint(uint8_t slot_index) {
  XInputSlotState& slot = g_slot_states[slot_index];
  if (!slot.interfaces_opened || slot.control_out_ep == 0) {
    return false;
  }
  return usbd_edpt_xfer(slot.rhport, slot.control_out_ep, slot.control_out_buffer, sizeof(slot.control_out_buffer));
}

bool xinputStartReportTransfer(uint8_t slot_index) {
  XInputSlotState& slot = g_slot_states[slot_index];
  if (!slot.interfaces_opened || slot.control_in_ep == 0 || slot.report_in_flight || !slot.host_out_seen || !tud_ready()) {
    return false;
  }
  if (!usbd_edpt_ready(slot.rhport, slot.control_in_ep)) {
    return false;
  }

  slot.transfer_report = slot.pending_report;
  slot.report_in_flight = usbd_edpt_xfer(slot.rhport, slot.control_in_ep,
                                         reinterpret_cast<uint8_t*>(&slot.transfer_report),
                                         sizeof(slot.transfer_report));
  if (slot.report_in_flight) {
    slot.report_dirty = false;
    slot.last_queued_report = slot.transfer_report;
    slot.has_queued_report = true;
    ++g_send_success_count;
    if (!xinputReportIsNeutral(slot.transfer_report)) {
      slot.has_sent_non_neutral_report = true;
    }
  }
  return slot.report_in_flight;
}

bool queueSlotReport(uint8_t slot_index, const XInputControlReport& report) {
  XInputSlotState& slot = g_slot_states[slot_index];
  if (!slot.interfaces_opened) {
    return false;
  }
  if (xinputReportIsNeutral(report) && !slot.has_sent_non_neutral_report) {
    slot.pending_report = report;
    slot.report_dirty = false;
    return true;
  }
  if (slot.report_in_flight && xinputReportsEqual(report, slot.transfer_report)) {
    return true;
  }
  if (slot.report_dirty && xinputReportsEqual(report, slot.pending_report)) {
    return !slot.report_in_flight ? xinputStartReportTransfer(slot_index) : true;
  }
  if (!slot.report_in_flight && slot.has_queued_report && xinputReportsEqual(report, slot.last_queued_report)) {
    return true;
  }
  slot.pending_report = report;
  slot.report_dirty = true;
  return xinputStartReportTransfer(slot_index);
}

bool xinputUsbInit() {
  static bool initialized = false;
  if (initialized) {
    return true;
  }
  buildDescriptors();
  if (tinyusb_enable_interface(USB_INTERFACE_CUSTOM, g_interface_descriptors.size(),
                               [](uint8_t* dst, uint8_t* itf) -> uint16_t {
                                 if (!g_logged_custom_descriptor) {
                                   esp_rom_printf("USBX: load custom descriptor itf=%u add=%u\n",
                                                  static_cast<unsigned>(*itf),
                                                  static_cast<unsigned>(config::kMaxControllerSlots));
                                   g_logged_custom_descriptor = true;
                                 }
                                 *itf = static_cast<uint8_t>(*itf + config::kMaxControllerSlots);
                                 memcpy(dst, g_interface_descriptors.data(), g_interface_descriptors.size());
                                 return g_interface_descriptors.size();
                               }) != ESP_OK) {
    return false;
  }

  initialized = true;
  USB.VID(kXbox360Vid);
  USB.PID(kXbox360Pid);
  USB.firmwareVersion(kXbox360BcdDevice);
  USB.usbVersion(0x0200);
  USB.usbClass(kVendorClass);
  USB.usbSubClass(kVendorClass);
  USB.usbProtocol(kVendorClass);
  USB.productName(config::kUsbXInputProductName);
  USB.manufacturerName("Microsoft");
  USB.serialNumber(config::kDeviceUuid);
  return true;
}

uint16_t copyUtf16StringDescriptor(const char* value, uint16_t* dst) {
  size_t length = strlen(value);
  if (length > 126) {
    length = 126;
  }
  dst[0] = static_cast<uint16_t>((TUSB_DESC_STRING << 8) | (2 * length + 2));
  for (size_t i = 0; i < length; ++i) {
    dst[1 + i] = value[i];
  }
  return dst[0];
}

void xinputDriverInit(void) {
  g_slot_states = {};
  g_logged_custom_descriptor = false;
  g_logged_device_descriptor = false;
  g_logged_config_descriptor = false;
  memset(g_logged_string_descriptor, 0, sizeof(g_logged_string_descriptor));
  g_send_attempt_count = 0;
  g_send_success_count = 0;
  g_in_xfer_complete_count = 0;
  g_in_xfer_failure_count = 0;
  g_out_xfer_complete_count = 0;
  g_active_slots = 0;
}

void xinputDriverReset(uint8_t rhport) {
  (void)rhport;
  xinputDriverInit();
}

uint16_t xinputDriverOpen(uint8_t rhport, tusb_desc_interface_t const* desc_intf, uint16_t max_len) {
  if (desc_intf->bInterfaceClass != kVendorClass || desc_intf->bInterfaceSubClass != kXInputSubClass ||
      desc_intf->bInterfaceProtocol != kXInputProtocol) {
    return 0;
  }

  const int8_t slot_index = slotIndexFromInterface(desc_intf->bInterfaceNumber);
  if (slot_index < 0) {
    return 0;
  }

  XInputSlotState& slot = g_slot_states[slot_index];
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

  xinputPrimeOutEndpoint(static_cast<uint8_t>(slot_index));
  return consumed;
}

bool xinputDriverControlXfer(uint8_t rhport, uint8_t stage, tusb_control_request_t const* request) {
  if (stage != CONTROL_STAGE_SETUP) {
    return true;
  }
  if (request->bmRequestType_bit.type != TUSB_REQ_TYPE_VENDOR || request->bRequest != 0x01) {
    return false;
  }

  if (request->bmRequestType_bit.direction == TUSB_DIR_IN) {
    if (request->wValue == 0x0000 && request->wIndex == 0x0000) {
      if (request->bmRequestType == 0xc0) {
        alignas(4) static auto serial = serialPacket();
        return tud_control_xfer(rhport, request, serial.data(), serial.size());
      }

      if (request->bmRequestType == 0xc1) {
        alignas(4) static uint8_t sram_feedback[kCapabilitiesFeedback.size()];
        memcpy(sram_feedback, kCapabilitiesFeedback.data(), kCapabilitiesFeedback.size());
        return tud_control_xfer(rhport, request, sram_feedback, kCapabilitiesFeedback.size());
      }
    }

    if (request->bmRequestType == 0xc1 && request->wValue == 0x0100) {
      alignas(4) static uint8_t sram_capabilities[kCapabilitiesInputs.size()];
      memcpy(sram_capabilities, kCapabilitiesInputs.data(), kCapabilitiesInputs.size());
      return tud_control_xfer(rhport, request, sram_capabilities, kCapabilitiesInputs.size());
    }

    return false;
  }

  return tud_control_status(rhport, request);
}

bool xinputDriverXfer(uint8_t rhport, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes) {
  const int8_t slot_index = slotIndexFromEndpoint(ep_addr);
  if (slot_index < 0) {
    return false;
  }

  XInputSlotState& slot = g_slot_states[slot_index];
  if (result != XFER_RESULT_SUCCESS) {
    if (ep_addr == slot.control_in_ep) {
      slot.report_in_flight = false;
      ++g_in_xfer_failure_count;
    } else if (ep_addr == slot.control_out_ep) {
      xinputPrimeOutEndpoint(static_cast<uint8_t>(slot_index));
    }
    return true;
  }

  if (ep_addr == slot.control_in_ep) {
    slot.report_in_flight = false;
    ++g_in_xfer_complete_count;
    if (slot.report_dirty) {
      xinputStartReportTransfer(static_cast<uint8_t>(slot_index));
    }
    (void)xferred_bytes;
    return true;
  }

  if (ep_addr == slot.control_out_ep) {
    slot.host_out_seen = true;
    ++g_out_xfer_complete_count;
    xinputPrimeOutEndpoint(static_cast<uint8_t>(slot_index));
    if (slot.report_dirty) {
      xinputStartReportTransfer(static_cast<uint8_t>(slot_index));
    }
  }
  (void)rhport;
  return true;
}
}  // namespace

extern "C" uint8_t const* tud_descriptor_device_cb(void) {
  if (!g_logged_device_descriptor) {
    g_logged_device_descriptor = true;
  }
  return reinterpret_cast<uint8_t const*>(&kXbox360DeviceDescriptor);
}

extern "C" uint8_t const* tud_descriptor_configuration_cb(uint8_t index) {
  (void)index;
  if (!g_logged_config_descriptor) {
    g_logged_config_descriptor = true;
  }
  buildDescriptors();
  return g_configuration_descriptor.data();
}

extern "C" uint16_t const* tud_descriptor_string_cb(uint8_t index, uint16_t langid) {
  (void)langid;
  static uint16_t descriptor[127];

  if (index < sizeof(g_logged_string_descriptor) && !g_logged_string_descriptor[index]) {
    g_logged_string_descriptor[index] = true;
  }

  if (index == kLanguageStringIndex) {
    descriptor[0] = static_cast<uint16_t>((TUSB_DESC_STRING << 8) | 4);
    descriptor[1] = 0x0409;
    return descriptor;
  }

  const char* value = nullptr;
  switch (index) {
    case kManufacturerStringIndex:
      value = "Microsoft";
      break;
    case kProductStringIndex:
      value = config::kUsbXInputProductName;
      break;
    case kSerialStringIndex:
      value = config::kDeviceUuid;
      break;
    default:
      return nullptr;
  }

  copyUtf16StringDescriptor(value, descriptor);
  return descriptor;
}

extern "C" usbd_class_driver_t const* usbd_app_driver_get_cb(uint8_t* driver_count) {
  static usbd_class_driver_t const kXInputDriver = {
#if CFG_TUSB_DEBUG >= CFG_TUD_LOG_LEVEL
      "xinput",
#endif
      xinputDriverInit,
      xinputDriverReset,
      xinputDriverOpen,
      xinputDriverControlXfer,
      xinputDriverXfer,
      nullptr,
  };

  *driver_count = 1;
  return &kXInputDriver;
}

bool UsbXInputGamepadBridge::begin() {
  for (uint32_t elapsed = 0; elapsed < config::kUsbXInputBootLogDelayMs; elapsed += config::kUsbXInputBootLogStepMs) {
    delay(config::kUsbXInputBootLogStepMs);
  }
  if (config::kUsbXInputDeferBegin) {
    deferred_start_ = true;
    return true;
  }
  if (!xinputUsbInit()) {
    return false;
  }
  USB.begin();
  started_ = true;
  return true;
}

void UsbXInputGamepadBridge::loop() {}

bool UsbXInputGamepadBridge::resetConnection() {
  return false;
}

bool UsbXInputGamepadBridge::setPairingEnabled(bool enabled) {
  (void)enabled;
  return false;
}

bool UsbXInputGamepadBridge::send(const HostInputReport& report) {
  return sendSlots(&report, 1, 0x01);
}

bool UsbXInputGamepadBridge::sendSlots(const HostInputReport* reports, uint8_t report_count, uint32_t active_slot_mask) {
  ++g_send_attempt_count;
  if (!started_ || deferred_start_ || reports == nullptr || !tud_ready()) {
    return false;
  }

  bool ok = true;
  g_active_slots = 0;
  const uint8_t capped_count = report_count > config::kMaxControllerSlots ? config::kMaxControllerSlots : report_count;
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    const bool active = i < capped_count && (active_slot_mask & (1u << i)) != 0;
    const XInputControlReport report = active ? reportFromHostInput(reports[i]) : XInputControlReport{};
    ok = queueSlotReport(i, report) && ok;
    if (active) {
      ++g_active_slots;
    }
  }
  return ok;
}

HostStatus UsbXInputGamepadBridge::status() const {
  HostStatus status;
  status.transport = "usb";
  status.variant = "pc";
  status.display_name = config::kUsbXInputProductName;
  status.ready = started_ && !deferred_start_;
  status.connected = started_ && !deferred_start_ && tud_mounted();
  status.supports_pairing = false;
  status.pairing_enabled = false;
  status.advertising = false;
  status.usb_active_slots = g_active_slots;
  status.usb_send_attempts = g_send_attempt_count;
  status.usb_send_successes = g_send_success_count;
  status.usb_in_completions = g_in_xfer_complete_count;
  status.usb_in_failures = g_in_xfer_failure_count;
  status.usb_out_completions = g_out_xfer_complete_count;
  return status;
}

#endif
