#pragma once

#include <stdint.h>

#include "config.h"
#include "input_mapper.h"

namespace multi_controller {
inline uint8_t cappedReportCount(uint8_t report_count) {
  return report_count > config::kMaxControllerSlots ? config::kMaxControllerSlots : report_count;
}

inline bool slotIsActive(uint32_t active_slot_mask, uint8_t slot_index) {
  return (active_slot_mask & (1u << slot_index)) != 0;
}

inline uint8_t countActiveSlots(uint8_t report_count, uint32_t active_slot_mask) {
  uint8_t active_slots = 0;
  const uint8_t capped_count = cappedReportCount(report_count);
  for (uint8_t i = 0; i < capped_count; ++i) {
    if (slotIsActive(active_slot_mask, i)) {
      ++active_slots;
    }
  }
  return active_slots;
}

inline int8_t firstActiveSlotIndex(uint8_t report_count, uint32_t active_slot_mask) {
  const uint8_t capped_count = cappedReportCount(report_count);
  for (uint8_t i = 0; i < capped_count; ++i) {
    if (slotIsActive(active_slot_mask, i)) {
      return static_cast<int8_t>(i);
    }
  }
  return -1;
}
}  // namespace multi_controller
