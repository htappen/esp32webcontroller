#pragma once

#include <Arduino.h>
#include <HardwareSerial.h>
#include <stdint.h>

#include "config.h"

namespace debug_log {
#if defined(CONTROLLER_BOARD_S3) && \
    (defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH) || defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT))
inline HardwareSerial& stream() {
  static HardwareSerial log_serial(0);
  return log_serial;
}
#endif

#if defined(CONTROLLER_DEBUG_LOGS)
inline void begin() {
#if defined(CONTROLLER_BOARD_S3) && \
    (defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH) || defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT))
  stream().begin(config::kUsbLogBaudRate, SERIAL_8N1, config::kUsbLogRxPin, config::kUsbLogTxPin);
#else
  Serial.begin(115200);
#endif
  delay(100);
}

template <typename... Args>
inline void printf(const char* fmt, Args... args) {
#if defined(CONTROLLER_BOARD_S3) && \
    (defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH) || defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT))
  stream().printf(fmt, args...);
  stream().flush();
#else
  Serial.printf(fmt, args...);
  Serial.flush();
#endif
}

template <typename... Args>
inline void printf(uint32_t now_ms, uint32_t* last_log_ms, uint32_t interval_ms, bool always, const char* fmt,
                   Args... args) {
#if defined(CONTROLLER_DEBUG_LOGS)
  if (always || last_log_ms == nullptr || interval_ms == 0 || now_ms - *last_log_ms >= interval_ms) {
    if (last_log_ms != nullptr) {
      *last_log_ms = now_ms;
    }
    printf(fmt, args...);
  }
#else
  (void)now_ms;
  (void)last_log_ms;
  (void)interval_ms;
  (void)always;
  (void)fmt;
#endif
}

inline void println(const char* text) {
#if defined(CONTROLLER_BOARD_S3) && \
    (defined(CONTROLLER_HOST_TRANSPORT_USB_SWITCH) || defined(CONTROLLER_HOST_TRANSPORT_USB_XINPUT))
  stream().println(text);
  stream().flush();
#else
  Serial.println(text);
  Serial.flush();
#endif
}

inline bool enabled() {
  return true;
}
#else
inline void begin() {}

template <typename... Args>
inline void printf(const char*, Args...) {}

template <typename... Args>
inline void printf(uint32_t, uint32_t*, uint32_t, bool, const char*, Args...) {}

inline void println(const char*) {}

inline bool enabled() {
  return false;
}
#endif
}  // namespace debug_log
