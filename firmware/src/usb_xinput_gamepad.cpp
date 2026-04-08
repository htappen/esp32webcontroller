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
constexpr uint8_t kVendorSubClass = 0xff;
constexpr uint8_t kVendorProtocol = 0xff;
constexpr uint8_t kInterfaceNumber = 0;
constexpr uint8_t kControlPacketLength = 20;
constexpr uint8_t kFeedbackPacketLength = 8;
constexpr uint8_t kEndpointPacketSize = 32;
constexpr uint8_t kEndpointZeroPacketSize = CFG_TUD_ENDPOINT0_SIZE;
constexpr uint16_t kXbox360ConfigurationTotalLength = 0x0099;
constexpr uint16_t kXbox360BcdDevice = 0x0114;
constexpr uint8_t kUsbAttributesBusPoweredRemoteWakeup = 0xa0;
constexpr uint16_t kUsbPowerMilliAmps = 500;
constexpr uint8_t kInterfaceCount = 4;
constexpr uint8_t kManufacturerStringIndex = 0x01;
constexpr uint8_t kProductStringIndex = 0x02;
constexpr uint8_t kSerialStringIndex = 0x03;
constexpr uint8_t kSecurityMethodStringIndex = 0x04;
constexpr uint8_t kLanguageStringIndex = 0x00;
constexpr uint16_t kXbox360InterfaceDescriptorLength = kXbox360ConfigurationTotalLength - TUD_CONFIG_DESC_LEN;

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
constexpr uint8_t kButtonGuide = 10;
constexpr uint8_t kButtonA = 12;
constexpr uint8_t kButtonB = 13;
constexpr uint8_t kButtonX = 14;
constexpr uint8_t kButtonY = 15;

struct __attribute__((packed)) XInputControlReport {
  uint8_t type = 0x00;
  uint8_t size = kControlPacketLength;
  uint16_t buttons = 0;
  uint8_t lt = 0;
  uint8_t rt = 0;
  int16_t lx = 0;
  int16_t ly = 0;
  int16_t rx = 0;
  int16_t ry = 0;
  uint8_t reserved[6] = {};
};

static_assert(sizeof(XInputControlReport) == kControlPacketLength);

XInputControlReport g_report;

struct XInputDriverState {
  bool interfaces_opened = false;
  uint8_t rhport = 0;
  uint8_t primary_interface = 0;
  uint8_t control_in_ep = 0;
  uint8_t control_out_ep = 0;
  uint8_t headset_in_ep = 0;
  uint8_t headset_out_ep = 0;
  uint8_t headset_aux_in_ep = 0;
  uint8_t headset_aux_out_ep = 0;
  uint8_t auxiliary_in_ep = 0;
  bool report_in_flight = false;
  bool report_dirty = false;
  XInputControlReport pending_report;
  uint8_t control_out_buffer[kEndpointPacketSize] = {};
  uint8_t headset_out_buffer[kEndpointPacketSize] = {};
  uint8_t headset_aux_out_buffer[kEndpointPacketSize] = {};
};

XInputDriverState g_driver_state;
bool g_logged_custom_descriptor = false;
bool g_logged_device_descriptor = false;
bool g_logged_config_descriptor = false;
bool g_logged_string_descriptor[5] = {};
uint32_t g_send_log_count = 0;
uint32_t g_start_transfer_log_count = 0;
uint32_t g_in_xfer_log_count = 0;
uint32_t g_out_xfer_log_count = 0;
uint32_t g_send_attempt_count = 0;
uint32_t g_send_success_count = 0;

constexpr uint32_t kMaxVerboseSendLogs = 24;
constexpr uint32_t kMaxVerboseTransferLogs = 32;

constexpr std::array<uint8_t, kFeedbackPacketLength> kCapabilitiesFeedback = {
    0x00, 0x08, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00,
};

constexpr std::array<uint8_t, kControlPacketLength> kCapabilitiesInputs = {
    0x00, 0x14, 0x3f, 0xf7, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
    0xc0, 0xff, 0xc0, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

constexpr tusb_desc_device_t kXbox360DeviceDescriptor = {
    .bLength = sizeof(tusb_desc_device_t),
    .bDescriptorType = TUSB_DESC_DEVICE,
    .bcdUSB = 0x0200,
    .bDeviceClass = kVendorClass,
    .bDeviceSubClass = kVendorSubClass,
    .bDeviceProtocol = kVendorProtocol,
    .bMaxPacketSize0 = kEndpointZeroPacketSize,
    .idVendor = kXbox360Vid,
    .idProduct = kXbox360Pid,
    .bcdDevice = kXbox360BcdDevice,
    .iManufacturer = kManufacturerStringIndex,
    .iProduct = kProductStringIndex,
    .iSerialNumber = kSerialStringIndex,
    .bNumConfigurations = 0x01,
};

constexpr std::array<uint8_t, kXbox360ConfigurationTotalLength> kXbox360ConfigurationDescriptor = {
    0x09, 0x02, 0x99, 0x00, 0x04, 0x01, 0x00, 0xA0, 0xFA,
    // Interface 0: Control Data
    0x09, 0x04, 0x00, 0x00, 0x02, 0xFF, 0x5D, 0x01, 0x00,
    0x11, 0x21, 0x00, 0x01, 0x01, 0x25, 0x81, 0x14, 0x00, 0x00, 0x00, 0x00, 0x13, 0x01, 0x08, 0x00, 0x00,
    0x07, 0x05, 0x81, 0x03, 0x20, 0x00, 0x04,
    0x07, 0x05, 0x01, 0x03, 0x20, 0x00, 0x08,
    // Interface 1: Headset / expansion
    0x09, 0x04, 0x01, 0x00, 0x04, 0xFF, 0x5D, 0x03, 0x00,
    0x1B, 0x21, 0x00, 0x01, 0x01, 0x01, 0x82, 0x40, 0x01, 0x02, 0x20, 0x16, 0x83, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x16, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x07, 0x05, 0x82, 0x03, 0x20, 0x00, 0x02,
    0x07, 0x05, 0x02, 0x03, 0x20, 0x00, 0x04,
    0x07, 0x05, 0x83, 0x03, 0x20, 0x00, 0x40,
    0x07, 0x05, 0x03, 0x03, 0x20, 0x00, 0x10,
    // Interface 2: Auxiliary
    0x09, 0x04, 0x02, 0x00, 0x01, 0xFF, 0x5D, 0x02, 0x00,
    0x09, 0x21, 0x00, 0x01, 0x01, 0x22, 0x84, 0x07, 0x00,
    0x07, 0x05, 0x84, 0x03, 0x20, 0x00, 0x10,
    // Interface 3: Security method
    0x09, 0x04, 0x03, 0x00, 0x00, 0xFF, 0xFD, 0x13, kSecurityMethodStringIndex,
    0x06, 0x41, 0x00, 0x01, 0x01, 0x03,
};

static_assert(kXbox360ConfigurationDescriptor.size() == kXbox360ConfigurationTotalLength);

constexpr const char* kSecurityMethodString =
    "Xbox Security Method 3, Version 1.00, Microsoft Corporation. All rights reserved.";

uint16_t xinputCustomLoadDescriptor(uint8_t* dst, uint8_t* itf);
void xinputDriverInit(void);
void xinputDriverReset(uint8_t rhport);
uint16_t xinputDriverOpen(uint8_t rhport, tusb_desc_interface_t const* desc_intf, uint16_t max_len);
bool xinputDriverControlXfer(uint8_t rhport, uint8_t stage, tusb_control_request_t const* request);
bool xinputDriverXfer(uint8_t rhport, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes);
bool xinputPrimeOutEndpoint(uint8_t rhport, uint8_t ep_addr);
bool xinputStartReportTransfer(void);

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
  (void)kButtonGuide;
  return buttons;
}

uint8_t* outBufferForEndpoint(uint8_t ep_addr) {
  switch (ep_addr) {
    case 0x01:
      return g_driver_state.control_out_buffer;
    case 0x02:
      return g_driver_state.headset_out_buffer;
    case 0x03:
      return g_driver_state.headset_aux_out_buffer;
    default:
      return nullptr;
  }
}

uint16_t interfaceSpanLength(tusb_desc_interface_t const* desc_intf, uint16_t max_len) {
  uint16_t consumed = 0;
  const uint8_t first_interface = desc_intf->bInterfaceNumber;
  auto const* desc = reinterpret_cast<uint8_t const*>(desc_intf);

  while (consumed < max_len) {
    const uint8_t len = tu_desc_len(desc);
    if (len == 0 || consumed + len > max_len) {
      return 0;
    }

    if (consumed != 0 && tu_desc_type(desc) == TUSB_DESC_INTERFACE) {
      const auto* next_interface = reinterpret_cast<tusb_desc_interface_t const*>(desc);
      if (next_interface->bInterfaceNumber >= static_cast<uint8_t>(first_interface + kInterfaceCount)) {
        break;
      }
    }

    consumed = static_cast<uint16_t>(consumed + len);
    desc = tu_desc_next(desc);
  }

  return consumed;
}

bool xinputUsbInit() {
  static bool initialized = false;
  if (initialized) {
    return true;
  }
  if (tinyusb_enable_interface(USB_INTERFACE_CUSTOM, kXbox360InterfaceDescriptorLength, xinputCustomLoadDescriptor) !=
      ESP_OK) {
    esp_rom_printf("USBX: tinyusb_enable_interface failed\n");
    return false;
  }
  initialized = true;
  USB.VID(kXbox360Vid);
  USB.PID(kXbox360Pid);
  USB.firmwareVersion(kXbox360BcdDevice);
  USB.usbVersion(0x0200);
  USB.usbClass(kVendorClass);
  USB.usbSubClass(kVendorSubClass);
  USB.usbProtocol(kVendorProtocol);
  USB.usbAttributes(kUsbAttributesBusPoweredRemoteWakeup);
  USB.usbPower(kUsbPowerMilliAmps);
  USB.productName("Controller");
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

uint16_t xinputCustomLoadDescriptor(uint8_t* dst, uint8_t* itf) {
  if (!g_logged_custom_descriptor) {
    esp_rom_printf("USBX: load custom descriptor itf=%u add=%u\n", static_cast<unsigned>(*itf),
                   static_cast<unsigned>(kInterfaceCount));
    g_logged_custom_descriptor = true;
  }
  *itf = static_cast<uint8_t>(*itf + kInterfaceCount);
  memcpy(dst, kXbox360ConfigurationDescriptor.data() + TUD_CONFIG_DESC_LEN, kXbox360InterfaceDescriptorLength);
  return kXbox360InterfaceDescriptorLength;
}

bool xinputPrimeOutEndpoint(uint8_t rhport, uint8_t ep_addr) {
  uint8_t* buffer = outBufferForEndpoint(ep_addr);
  if (buffer == nullptr) {
    return false;
  }
  const bool queued = usbd_edpt_xfer(rhport, ep_addr, buffer, sizeof(g_driver_state.control_out_buffer));
  if (g_out_xfer_log_count < kMaxVerboseTransferLogs) {
    esp_rom_printf("USBX: prime out ep=0x%02x queued=%u\n", static_cast<unsigned>(ep_addr), queued ? 1u : 0u);
  }
  return queued;
}

bool xinputStartReportTransfer() {
  if (!g_driver_state.interfaces_opened || g_driver_state.control_in_ep == 0 || g_driver_state.report_in_flight) {
    if (g_start_transfer_log_count < kMaxVerboseTransferLogs) {
      esp_rom_printf("USBX: start xfer blocked open=%u in_ep=0x%02x inflight=%u dirty=%u\n",
                     g_driver_state.interfaces_opened ? 1u : 0u, static_cast<unsigned>(g_driver_state.control_in_ep),
                     g_driver_state.report_in_flight ? 1u : 0u, g_driver_state.report_dirty ? 1u : 0u);
      ++g_start_transfer_log_count;
    }
    return false;
  }

  const bool tud_is_ready = tud_ready();
  const bool ep_ready = tud_is_ready && usbd_edpt_ready(g_driver_state.rhport, g_driver_state.control_in_ep);
  if (!tud_is_ready || !ep_ready) {
    if (g_start_transfer_log_count < kMaxVerboseTransferLogs) {
      esp_rom_printf("USBX: start xfer not ready tud=%u ep=0x%02x ep_ready=%u dirty=%u\n", tud_is_ready ? 1u : 0u,
                     static_cast<unsigned>(g_driver_state.control_in_ep), ep_ready ? 1u : 0u,
                     g_driver_state.report_dirty ? 1u : 0u);
      ++g_start_transfer_log_count;
    }
    return false;
  }

  g_driver_state.report_in_flight = usbd_edpt_xfer(g_driver_state.rhport, g_driver_state.control_in_ep,
                                                   reinterpret_cast<uint8_t*>(&g_driver_state.pending_report),
                                                   sizeof(g_driver_state.pending_report));
  if (g_start_transfer_log_count < kMaxVerboseTransferLogs) {
    esp_rom_printf("USBX: start xfer ep=0x%02x queued=%u buttons=0x%04x lt=%u rt=%u lx=%d ly=%d rx=%d ry=%d\n",
                   static_cast<unsigned>(g_driver_state.control_in_ep), g_driver_state.report_in_flight ? 1u : 0u,
                   static_cast<unsigned>(g_driver_state.pending_report.buttons),
                   static_cast<unsigned>(g_driver_state.pending_report.lt),
                   static_cast<unsigned>(g_driver_state.pending_report.rt), g_driver_state.pending_report.lx,
                   g_driver_state.pending_report.ly, g_driver_state.pending_report.rx, g_driver_state.pending_report.ry);
    ++g_start_transfer_log_count;
  }
  if (g_driver_state.report_in_flight) {
    g_driver_state.report_dirty = false;
  }
  return g_driver_state.report_in_flight;
}

void xinputDriverInit(void) {
  g_driver_state = XInputDriverState{};
  g_logged_custom_descriptor = false;
  g_logged_device_descriptor = false;
  g_logged_config_descriptor = false;
  memset(g_logged_string_descriptor, 0, sizeof(g_logged_string_descriptor));
  g_send_log_count = 0;
  g_start_transfer_log_count = 0;
  g_in_xfer_log_count = 0;
  g_out_xfer_log_count = 0;
  g_send_attempt_count = 0;
  g_send_success_count = 0;
}

void xinputDriverReset(uint8_t rhport) {
  (void)rhport;
  xinputDriverInit();
}

uint16_t xinputDriverOpen(uint8_t rhport, tusb_desc_interface_t const* desc_intf, uint16_t max_len) {
  esp_rom_printf("USBX: driver open cls=%u sub=%u proto=%u itf=%u len=%u\n",
                 static_cast<unsigned>(desc_intf->bInterfaceClass),
                 static_cast<unsigned>(desc_intf->bInterfaceSubClass),
                 static_cast<unsigned>(desc_intf->bInterfaceProtocol),
                 static_cast<unsigned>(desc_intf->bInterfaceNumber), static_cast<unsigned>(max_len));
  if (desc_intf->bInterfaceClass != kVendorClass || desc_intf->bInterfaceSubClass != 0x5d ||
      desc_intf->bInterfaceProtocol != 0x01) {
    esp_rom_printf("USBX: driver open rejected\n");
    return 0;
  }

  const uint16_t span_len = interfaceSpanLength(desc_intf, max_len);
  if (span_len == 0) {
    esp_rom_printf("USBX: driver open span=0\n");
    return 0;
  }

  g_driver_state = XInputDriverState{};
  g_driver_state.interfaces_opened = true;
  g_driver_state.rhport = rhport;
  g_driver_state.primary_interface = desc_intf->bInterfaceNumber;

  auto const* desc = reinterpret_cast<uint8_t const*>(desc_intf);
  const auto* const end = desc + span_len;
  uint8_t current_interface = desc_intf->bInterfaceNumber;

  while (desc < end) {
    const uint8_t type = tu_desc_type(desc);

    if (type == TUSB_DESC_INTERFACE) {
      current_interface = reinterpret_cast<tusb_desc_interface_t const*>(desc)->bInterfaceNumber;
    } else if (type == TUSB_DESC_ENDPOINT) {
      auto const* ep_desc = reinterpret_cast<tusb_desc_endpoint_t const*>(desc);
      if (!usbd_edpt_open(rhport, ep_desc)) {
        g_driver_state.interfaces_opened = false;
        esp_rom_printf("USBX: ep open failed addr=0x%02x\n", static_cast<unsigned>(ep_desc->bEndpointAddress));
        return 0;
      }

      switch (current_interface) {
        case 0:
          if (tu_edpt_dir(ep_desc->bEndpointAddress) == TUSB_DIR_IN) {
            g_driver_state.control_in_ep = ep_desc->bEndpointAddress;
          } else {
            g_driver_state.control_out_ep = ep_desc->bEndpointAddress;
          }
          break;
        case 1:
          if (tu_edpt_dir(ep_desc->bEndpointAddress) == TUSB_DIR_IN) {
            if (g_driver_state.headset_in_ep == 0) {
              g_driver_state.headset_in_ep = ep_desc->bEndpointAddress;
            } else {
              g_driver_state.headset_aux_in_ep = ep_desc->bEndpointAddress;
            }
          } else {
            if (g_driver_state.headset_out_ep == 0) {
              g_driver_state.headset_out_ep = ep_desc->bEndpointAddress;
            } else {
              g_driver_state.headset_aux_out_ep = ep_desc->bEndpointAddress;
            }
          }
          break;
        case 2:
          if (tu_edpt_dir(ep_desc->bEndpointAddress) == TUSB_DIR_IN) {
            g_driver_state.auxiliary_in_ep = ep_desc->bEndpointAddress;
          }
          break;
        default:
          break;
      }
    }

    desc = tu_desc_next(desc);
  }

  xinputPrimeOutEndpoint(rhport, g_driver_state.control_out_ep);
  xinputPrimeOutEndpoint(rhport, g_driver_state.headset_out_ep);
  xinputPrimeOutEndpoint(rhport, g_driver_state.headset_aux_out_ep);
  esp_rom_printf(
      "USBX: driver open ok span=%u in=0x%02x out=0x%02x hs_in=0x%02x hs_out=0x%02x aux=0x%02x\n",
      static_cast<unsigned>(span_len), static_cast<unsigned>(g_driver_state.control_in_ep),
      static_cast<unsigned>(g_driver_state.control_out_ep), static_cast<unsigned>(g_driver_state.headset_in_ep),
      static_cast<unsigned>(g_driver_state.headset_out_ep), static_cast<unsigned>(g_driver_state.auxiliary_in_ep));
  return span_len;
}

bool xinputDriverControlXfer(uint8_t rhport, uint8_t stage, tusb_control_request_t const* request) {
  if (stage != CONTROL_STAGE_SETUP) {
    return true;
  }

  if (request->bmRequestType_bit.type != TUSB_REQ_TYPE_VENDOR || request->bRequest != 0x01) {
    esp_rom_printf("USBX: ctrl unsupported bm=0x%02x req=0x%02x val=0x%04x idx=0x%04x len=%u\n",
                   static_cast<unsigned>(request->bmRequestType), static_cast<unsigned>(request->bRequest),
                   static_cast<unsigned>(request->wValue), static_cast<unsigned>(request->wIndex),
                   static_cast<unsigned>(request->wLength));
    return false;
  }

  esp_rom_printf("USBX: ctrl bm=0x%02x req=0x%02x val=0x%04x idx=0x%04x len=%u\n",
                 static_cast<unsigned>(request->bmRequestType), static_cast<unsigned>(request->bRequest),
                 static_cast<unsigned>(request->wValue), static_cast<unsigned>(request->wIndex),
                 static_cast<unsigned>(request->wLength));

  if (request->bmRequestType_bit.direction == TUSB_DIR_IN) {
    if (request->wValue == 0x0000 && request->wIndex == 0x0000) {
      if (request->bmRequestType == 0xc0) {
        auto serial = serialPacket();
        return tud_control_xfer(rhport, request, serial.data(), serial.size());
      }

      if (request->bmRequestType == 0xc1) {
        return tud_control_xfer(rhport, request, const_cast<uint8_t*>(kCapabilitiesFeedback.data()),
                                kCapabilitiesFeedback.size());
      }
    }

    if (request->bmRequestType == 0xc1 && request->wValue == 0x0100) {
      return tud_control_xfer(rhport, request, const_cast<uint8_t*>(kCapabilitiesInputs.data()),
                              kCapabilitiesInputs.size());
    }

    return false;
  }

  return tud_control_status(rhport, request);
}

bool xinputDriverXfer(uint8_t rhport, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes) {
  if (!g_driver_state.interfaces_opened || result != XFER_RESULT_SUCCESS) {
    if (ep_addr == g_driver_state.control_in_ep) {
      g_driver_state.report_in_flight = false;
      if (g_in_xfer_log_count < kMaxVerboseTransferLogs) {
        esp_rom_printf("USBX: in xfer incomplete ep=0x%02x result=%u bytes=%u dirty=%u\n",
                       static_cast<unsigned>(ep_addr), static_cast<unsigned>(result),
                       static_cast<unsigned>(xferred_bytes), g_driver_state.report_dirty ? 1u : 0u);
        ++g_in_xfer_log_count;
      }
    } else if (tu_edpt_dir(ep_addr) == TUSB_DIR_OUT) {
      if (g_out_xfer_log_count < kMaxVerboseTransferLogs) {
        const uint8_t* buffer = outBufferForEndpoint(ep_addr);
        esp_rom_printf("USBX: out xfer incomplete ep=0x%02x result=%u bytes=%u data=%02x %02x %02x %02x\n",
                       static_cast<unsigned>(ep_addr), static_cast<unsigned>(result),
                       static_cast<unsigned>(xferred_bytes), buffer != nullptr ? buffer[0] : 0u,
                       buffer != nullptr ? buffer[1] : 0u, buffer != nullptr ? buffer[2] : 0u,
                       buffer != nullptr ? buffer[3] : 0u);
        ++g_out_xfer_log_count;
      }
      xinputPrimeOutEndpoint(rhport, ep_addr);
    }
    return true;
  }

  if (ep_addr == g_driver_state.control_in_ep) {
    g_driver_state.report_in_flight = false;
    if (g_in_xfer_log_count < kMaxVerboseTransferLogs) {
      esp_rom_printf("USBX: in xfer complete ep=0x%02x bytes=%u dirty=%u success=%u/%u\n",
                     static_cast<unsigned>(ep_addr), static_cast<unsigned>(xferred_bytes),
                     g_driver_state.report_dirty ? 1u : 0u, static_cast<unsigned>(g_send_success_count),
                     static_cast<unsigned>(g_send_attempt_count));
      ++g_in_xfer_log_count;
    }
    if (g_driver_state.report_dirty) {
      xinputStartReportTransfer();
    }
    return true;
  }

  if (tu_edpt_dir(ep_addr) == TUSB_DIR_OUT) {
    if (g_out_xfer_log_count < kMaxVerboseTransferLogs) {
      const uint8_t* buffer = outBufferForEndpoint(ep_addr);
      esp_rom_printf("USBX: out xfer complete ep=0x%02x bytes=%u data=%02x %02x %02x %02x %02x %02x %02x %02x\n",
                     static_cast<unsigned>(ep_addr), static_cast<unsigned>(xferred_bytes),
                     buffer != nullptr ? buffer[0] : 0u, buffer != nullptr ? buffer[1] : 0u,
                     buffer != nullptr ? buffer[2] : 0u, buffer != nullptr ? buffer[3] : 0u,
                     buffer != nullptr ? buffer[4] : 0u, buffer != nullptr ? buffer[5] : 0u,
                     buffer != nullptr ? buffer[6] : 0u, buffer != nullptr ? buffer[7] : 0u);
      ++g_out_xfer_log_count;
    }
    xinputPrimeOutEndpoint(rhport, ep_addr);
  }

  return true;
}
}  // namespace

extern "C" uint8_t const* tud_descriptor_device_cb(void) {
  if (!g_logged_device_descriptor) {
    esp_rom_printf("USBX: device descriptor cb\n");
    g_logged_device_descriptor = true;
  }
  return reinterpret_cast<uint8_t const*>(&kXbox360DeviceDescriptor);
}

extern "C" uint8_t const* tud_descriptor_configuration_cb(uint8_t index) {
  if (!g_logged_config_descriptor) {
    esp_rom_printf("USBX: config descriptor cb index=%u\n", static_cast<unsigned>(index));
    g_logged_config_descriptor = true;
  }
  (void)index;
  return kXbox360ConfigurationDescriptor.data();
}

extern "C" uint16_t const* tud_descriptor_string_cb(uint8_t index, uint16_t langid) {
  (void)langid;
  static uint16_t descriptor[127];

  if (index < sizeof(g_logged_string_descriptor) && !g_logged_string_descriptor[index]) {
    esp_rom_printf("USBX: string descriptor cb index=%u\n", static_cast<unsigned>(index));
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
      value = "Controller";
      break;
    case kSerialStringIndex:
      value = config::kDeviceUuid;
      break;
    case kSecurityMethodStringIndex:
      value = kSecurityMethodString;
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
    esp_rom_printf("USBX: begin defer=1\n");
    deferred_start_ = true;
    return true;
  }
  esp_rom_printf("USBX: before xinputUsbInit\n");
  if (!xinputUsbInit()) {
    esp_rom_printf("USBX: xinputUsbInit failed\n");
    return false;
  }
  esp_rom_printf("USBX: after xinputUsbInit\n");
  esp_rom_printf("USBX: before USB.begin\n");
  USB.begin();
  esp_rom_printf("USBX: after USB.begin\n");
  started_ = true;
  g_report = XInputControlReport{};
  esp_rom_printf("USBX: begin complete\n");
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
  ++g_send_attempt_count;
  const bool tud_is_ready = tud_ready();
  const bool ep_ready = g_driver_state.interfaces_opened && g_driver_state.control_in_ep != 0 &&
                        usbd_edpt_ready(g_driver_state.rhport, g_driver_state.control_in_ep);
  if (!started_ || deferred_start_ || !g_driver_state.interfaces_opened || !tud_is_ready) {
    if (g_send_log_count < kMaxVerboseSendLogs) {
      esp_rom_printf("USBX: send blocked started=%u deferred=%u open=%u tud=%u in_ep=0x%02x ep_ready=%u\n",
                     started_ ? 1u : 0u, deferred_start_ ? 1u : 0u, g_driver_state.interfaces_opened ? 1u : 0u,
                     tud_is_ready ? 1u : 0u, static_cast<unsigned>(g_driver_state.control_in_ep), ep_ready ? 1u : 0u);
      ++g_send_log_count;
    }
    return false;
  }

  g_report.buttons = buttonsFromReport(report);
  g_report.lt = report.lt;
  g_report.rt = report.rt;
  g_report.lx = report.lx;
  g_report.ly = report.ly;
  g_report.rx = report.rx;
  g_report.ry = report.ry;

  g_driver_state.pending_report = g_report;
  g_driver_state.report_dirty = true;
  const bool queued = xinputStartReportTransfer();
  if (queued) {
    ++g_send_success_count;
  }
  if (g_send_log_count < kMaxVerboseSendLogs) {
    esp_rom_printf("USBX: send queued=%u buttons=0x%04x lt=%u rt=%u lx=%d ly=%d rx=%d ry=%d ep_ready=%u\n",
                   queued ? 1u : 0u, static_cast<unsigned>(g_report.buttons), static_cast<unsigned>(g_report.lt),
                   static_cast<unsigned>(g_report.rt), g_report.lx, g_report.ly, g_report.rx, g_report.ry,
                   ep_ready ? 1u : 0u);
    ++g_send_log_count;
  }
  return queued;
}

HostStatus UsbXInputGamepadBridge::status() const {
  HostStatus status;
  status.transport = "usb";
  status.variant = "pc";
  status.display_name = config::kUsbXInputProductName;
  status.ready = started_ && !deferred_start_ && g_driver_state.interfaces_opened;
  status.connected = started_ && !deferred_start_ && tud_mounted();
  status.supports_pairing = false;
  status.pairing_enabled = false;
  status.advertising = false;
  return status;
}

#endif
