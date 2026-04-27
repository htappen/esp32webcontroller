#pragma once

#include <Arduino.h>

#include "config.h"

namespace debug_log {
#if defined(CONTROLLER_DEBUG_LOGS)
inline void begin() {
#if defined(CONTROLLER_BOARD_S3) && \
    (defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH) || defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT))
  Serial.begin(config::kUsbLogBaudRate, SERIAL_8N1, config::kUsbLogRxPin, config::kUsbLogTxPin);
#else
  Serial.begin(115200);
#endif
  delay(100);
}

template <typename... Args>
inline void printf(const char* fmt, Args... args) {
  Serial.printf(fmt, args...);
}

inline void println(const char* text) {
  Serial.println(text);
}

inline bool enabled() {
  return true;
}
#else
inline void begin() {}

template <typename... Args>
inline void printf(const char*, Args...) {}

inline void println(const char*) {}

inline bool enabled() {
  return false;
}
#endif
}  // namespace debug_log
