#include "usb_switch_gamepad.h"

#if defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH)

#include <Arduino.h>
#include <USB.h>
#include <USBHID.h>

#include "config.h"

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
constexpr uint8_t kHatCentered = 8;
constexpr uint8_t kTriggerButtonThreshold = 32;

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
constexpr uint8_t kReportDescriptor[] = {
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

class NintendoSwitchUsbDevice : public USBHIDDevice {
 public:
  NintendoSwitchUsbDevice() {
    static bool initialized = false;
    USB.VID(kNintendoSwitchVid);
    USB.PID(kNintendoSwitchPid);
    USB.usbClass(0);
    USB.usbSubClass(0);
    USB.usbProtocol(0);
    USB.productName(config::kUsbSwitchProductName);
    USB.manufacturerName("ESP32 Controller");
    USB.serialNumber(config::kDeviceUuid);
    if (!initialized) {
      initialized = true;
      hid_.addDevice(this, sizeof(kReportDescriptor));
    }
  }

  void begin() {
    hid_.begin();
    reset();
  }

  bool ready() const {
    return const_cast<USBHID&>(hid_).ready();
  }

  bool mounted() const {
    return static_cast<bool>(USB);
  }

  void reset() {
    report_ = NintendoSwitchReport{};
  }

  bool send(const HostInputReport& report) {
    report_.buttons = 0;
    if (report.btn.y) report_.buttons |= (1u << kButtonY);
    if (report.btn.b) report_.buttons |= (1u << kButtonB);
    if (report.btn.a) report_.buttons |= (1u << kButtonA);
    if (report.btn.x) report_.buttons |= (1u << kButtonX);
    if (report.btn.lb) report_.buttons |= (1u << kButtonL);
    if (report.btn.rb) report_.buttons |= (1u << kButtonR);
    if (report.lt >= kTriggerButtonThreshold) report_.buttons |= (1u << kButtonZl);
    if (report.rt >= kTriggerButtonThreshold) report_.buttons |= (1u << kButtonZr);
    if (report.btn.back) report_.buttons |= (1u << kButtonMinus);
    if (report.btn.start) report_.buttons |= (1u << kButtonPlus);
    if (report.btn.ls) report_.buttons |= (1u << kButtonLStick);
    if (report.btn.rs) report_.buttons |= (1u << kButtonRStick);

    report_.hat = hatFromButtons(report.btn);
    report_.left_x = axisToUint8(report.lx);
    report_.left_y = axisToUint8(report.ly);
    report_.right_x = axisToUint8(report.rx);
    report_.right_y = axisToUint8(report.ry);
    report_.reserved = 0;

    if (!ready()) {
      return false;
    }
    return hid_.SendReport(0, &report_, sizeof(report_));
  }

  uint16_t _onGetDescriptor(uint8_t* dst) override {
    memcpy(dst, kReportDescriptor, sizeof(kReportDescriptor));
    return sizeof(kReportDescriptor);
  }

 private:
  static uint8_t axisToUint8(int16_t axis) {
    const int32_t shifted = static_cast<int32_t>(axis) + 32767;
    return static_cast<uint8_t>((shifted * 255) / 65534);
  }

  static uint8_t hatFromButtons(const Buttons& btn) {
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

  USBHID hid_;
  NintendoSwitchReport report_;
};

NintendoSwitchUsbDevice g_usb_gamepad;
}  // namespace

bool UsbSwitchGamepadBridge::begin() {
  g_usb_gamepad.begin();
  USB.begin();
  started_ = true;
  Serial.printf("USB host ready: transport=usb variant=switch board=%s vid=%04x pid=%04x\n", config::kBoardName,
                kNintendoSwitchVid, kNintendoSwitchPid);
  return true;
}

void UsbSwitchGamepadBridge::loop() {}

bool UsbSwitchGamepadBridge::resetConnection() {
  return false;
}

bool UsbSwitchGamepadBridge::setPairingEnabled(bool enabled) {
  (void)enabled;
  return false;
}

bool UsbSwitchGamepadBridge::send(const HostInputReport& report) {
  if (!started_) {
    return false;
  }
  return g_usb_gamepad.send(report);
}

HostStatus UsbSwitchGamepadBridge::status() const {
  HostStatus status;
  status.transport = "usb";
  status.variant = "switch";
  status.display_name = config::kUsbSwitchProductName;
  status.ready = started_ && g_usb_gamepad.ready();
  status.connected = started_ && g_usb_gamepad.mounted();
  status.supports_pairing = false;
  status.pairing_enabled = false;
  status.advertising = false;
  return status;
}

#endif
