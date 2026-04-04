#include "usb_xinput_gamepad.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT)

#include <Arduino.h>
#include <USB.h>

#include <array>
#include <cstring>

#include "common/tusb_common.h"
#include "common/tusb_types.h"
#include "class/vendor/vendor_device.h"
#include "config.h"
#include "esp32-hal-tinyusb.h"

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
constexpr uint8_t kEndpointZeroPacketSize = 8;
constexpr uint16_t kXbox360ConfigurationTotalLength = 0x0099;
constexpr uint16_t kXbox360BcdDevice = 0x0114;
constexpr uint8_t kUsbAttributesBusPoweredRemoteWakeup = 0xa0;
constexpr uint16_t kUsbPowerMilliAmps = 500;
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

uint16_t xinputVendorLoadDescriptor(uint8_t* dst, uint8_t* itf);

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

void xinputUsbInit() {
  static bool initialized = false;
  if (initialized) {
    return;
  }
  initialized = true;

  tinyusb_enable_interface(USB_INTERFACE_VENDOR, kXbox360InterfaceDescriptorLength, xinputVendorLoadDescriptor);
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

uint16_t xinputVendorLoadDescriptor(uint8_t* dst, uint8_t* itf) {
  *itf += 4;
  memcpy(dst, kXbox360ConfigurationDescriptor.data() + TUD_CONFIG_DESC_LEN, kXbox360InterfaceDescriptorLength);
  return kXbox360InterfaceDescriptorLength;
}
}  // namespace

extern "C" uint8_t const* tud_descriptor_device_cb(void) {
  return reinterpret_cast<uint8_t const*>(&kXbox360DeviceDescriptor);
}

extern "C" uint8_t const* tud_descriptor_configuration_cb(uint8_t index) {
  (void)index;
  return kXbox360ConfigurationDescriptor.data();
}

extern "C" uint16_t const* tud_descriptor_string_cb(uint8_t index, uint16_t langid) {
  (void)langid;
  static uint16_t descriptor[127];

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

extern "C" bool tinyusb_vendor_control_request_cb(uint8_t rhport, uint8_t stage, tusb_control_request_t const* request) {
  if (stage != CONTROL_STAGE_SETUP) {
    return true;
  }

  if (request->bRequest != 0x01 || request->wIndex != 0x0000) {
    return false;
  }

  if (request->bmRequestType == 0xc0 && request->wValue == 0x0000) {
    auto serial = serialPacket();
    return tud_control_xfer(rhport, request, serial.data(), serial.size());
  }

  if (request->bmRequestType != 0xc1) {
    return false;
  }

  if (request->wValue == 0x0000) {
    return tud_control_xfer(rhport, request, const_cast<uint8_t*>(kCapabilitiesFeedback.data()),
                            kCapabilitiesFeedback.size());
  }

  if (request->wValue == 0x0100) {
    return tud_control_xfer(rhport, request, const_cast<uint8_t*>(kCapabilitiesInputs.data()),
                            kCapabilitiesInputs.size());
  }

  return false;
}

extern "C" void tud_vendor_rx_cb(uint8_t itf) {
  if (itf != kInterfaceNumber) {
    return;
  }

  uint8_t buffer[kEndpointPacketSize];
  const uint32_t available = tud_vendor_n_available(itf);
  if (available == 0) {
    return;
  }

  const uint32_t count = tud_vendor_n_read(itf, buffer, sizeof(buffer));
  if (count >= 5 && buffer[0] == 0x00 && buffer[1] == 0x08) {
    Serial.printf("USB XInput feedback: left=%u right=%u\n", buffer[3], buffer[4]);
  } else if (count >= 3 && buffer[0] == 0x01) {
    Serial.printf("USB XInput LED mode: %u\n", buffer[2]);
  }
}

bool UsbXInputGamepadBridge::begin() {
  xinputUsbInit();
  USB.begin();
  started_ = true;
  g_report = XInputControlReport{};
  Serial.printf("USB host ready: transport=usb variant=pc board=%s vid=%04x pid=%04x\n", config::kBoardName,
                kXbox360Vid, kXbox360Pid);
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
  if (!started_ || !tud_vendor_n_mounted(kInterfaceNumber)) {
    return false;
  }

  g_report.buttons = buttonsFromReport(report);
  g_report.lt = report.lt;
  g_report.rt = report.rt;
  g_report.lx = report.lx;
  g_report.ly = report.ly;
  g_report.rx = report.rx;
  g_report.ry = report.ry;

  if (tud_vendor_n_write(kInterfaceNumber, &g_report, sizeof(g_report)) != sizeof(g_report)) {
    return false;
  }
  tud_vendor_n_write_flush(kInterfaceNumber);
  return true;
}

HostStatus UsbXInputGamepadBridge::status() const {
  HostStatus status;
  status.transport = "usb";
  status.variant = "pc";
  status.display_name = config::kUsbXInputProductName;
  status.ready = started_;
  status.connected = started_ && tud_vendor_n_mounted(kInterfaceNumber);
  status.supports_pairing = false;
  status.pairing_enabled = false;
  status.advertising = false;
  return status;
}

#endif
