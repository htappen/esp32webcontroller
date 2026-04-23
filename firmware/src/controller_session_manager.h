#pragma once

#include <cstddef>
#include <stdint.h>

#include "config.h"
#include "state_store.h"

struct ControllerSlotSnapshot {
  bool assigned = false;
  bool connected = false;
  bool reserved = false;
  bool active = false;
  uint8_t slot_number = 0;
  uint32_t last_packet_age_ms = 0;
  ControllerState state;
};

struct ControllerFleetSnapshot {
  bool ws_connected = false;
  uint8_t max_slots = 0;
  uint8_t assigned_slots = 0;
  uint8_t connected_slots = 0;
  uint8_t active_slots = 0;
  uint32_t active_slot_mask = 0;
  ControllerSlotSnapshot slots[config::kMaxControllerSlots];
};

enum class ControllerBindResult : uint8_t {
  kAssigned = 0,
  kReassigned = 1,
  kFull = 2,
  kInvalidClientId = 3,
};

struct ControllerBindOutcome {
  ControllerBindResult result = ControllerBindResult::kInvalidClientId;
  uint8_t slot_number = 0;
  uint8_t previous_ws_client_num = 0xff;
};

class ControllerSessionManager {
 public:
  void reset();
  void setCapacity(uint8_t slots);
  uint8_t capacity() const;

  ControllerBindOutcome bindClient(uint8_t ws_client_num, const char* client_id, uint32_t now_ms);
  bool getStateForClient(uint8_t ws_client_num, ControllerState* out) const;
  bool applyStateForClient(uint8_t ws_client_num, const ControllerState& next, uint32_t now_ms);
  bool disconnectClient(uint8_t ws_client_num, uint32_t now_ms);
  uint8_t collectTimedOutClients(uint32_t now_ms, uint8_t* out_ws_clients, uint8_t max_out);
  void evictExpiredReservations(uint32_t now_ms);
  void resetAllStates();
  ControllerFleetSnapshot snapshot(uint32_t now_ms) const;

 private:
  static constexpr uint8_t kUnboundWsClient = 0xff;
  static constexpr size_t kClientIdCapacity = 37;

  struct SlotRecord {
    bool assigned = false;
    bool connected = false;
    char client_id[kClientIdCapacity] = {};
    uint8_t ws_client_num = kUnboundWsClient;
    uint32_t last_packet_ms = 0;
    uint32_t grace_deadline_ms = 0;
    ControllerState state;
  };

  int8_t findSlotByWsClient(uint8_t ws_client_num) const;
  int8_t findSlotByClientId(const char* client_id) const;
  int8_t findFreeSlot(uint32_t now_ms) const;
  bool reservationExpired(const SlotRecord& slot, uint32_t now_ms) const;
  void clearSlot(uint8_t slot_index);
  void terminateSlot(uint8_t slot_index, uint32_t now_ms);

  uint8_t capacity_ = 1;
  SlotRecord slots_[config::kMaxControllerSlots];
};
