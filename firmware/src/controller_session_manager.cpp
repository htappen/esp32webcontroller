#include "controller_session_manager.h"

#include <string.h>

namespace {
uint8_t clamp_capacity(uint8_t slots) {
  if (slots == 0) {
    return 1;
  }
  return slots > config::kMaxControllerSlots ? config::kMaxControllerSlots : slots;
}
}  // namespace

void ControllerSessionManager::reset() {
  capacity_ = 1;
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    clearSlot(i);
  }
}

void ControllerSessionManager::setCapacity(uint8_t slots) {
  capacity_ = clamp_capacity(slots);
  for (uint8_t i = capacity_; i < config::kMaxControllerSlots; ++i) {
    clearSlot(i);
  }
}

uint8_t ControllerSessionManager::capacity() const {
  return capacity_;
}

ControllerBindOutcome ControllerSessionManager::bindClient(uint8_t ws_client_num, const char* client_id, uint32_t now_ms) {
  ControllerBindOutcome outcome;
  if (client_id == nullptr || client_id[0] == '\0' || strlen(client_id) >= kClientIdCapacity) {
    return outcome;
  }

  evictExpiredReservations(now_ms);

  int8_t slot_index = findSlotByClientId(client_id);
  if (slot_index >= 0) {
    SlotRecord& slot = slots_[slot_index];
    outcome.result = slot.connected ? ControllerBindResult::kReassigned : ControllerBindResult::kAssigned;
    outcome.slot_number = static_cast<uint8_t>(slot_index + 1);
    outcome.previous_ws_client_num = slot.connected ? slot.ws_client_num : kUnboundWsClient;
    slot.connected = true;
    slot.assigned = true;
    slot.ws_client_num = ws_client_num;
    slot.last_packet_ms = now_ms;
    slot.grace_deadline_ms = 0;
    slot.state = ControllerState{};
    return outcome;
  }

  slot_index = findFreeSlot(now_ms);
  if (slot_index < 0) {
    outcome.result = ControllerBindResult::kFull;
    return outcome;
  }

  SlotRecord& slot = slots_[slot_index];
  clearSlot(static_cast<uint8_t>(slot_index));
  slot.assigned = true;
  slot.connected = true;
  slot.ws_client_num = ws_client_num;
  slot.last_packet_ms = now_ms;
  strncpy(slot.client_id, client_id, sizeof(slot.client_id) - 1);
  slot.client_id[sizeof(slot.client_id) - 1] = '\0';
  outcome.result = ControllerBindResult::kAssigned;
  outcome.slot_number = static_cast<uint8_t>(slot_index + 1);
  return outcome;
}

bool ControllerSessionManager::getStateForClient(uint8_t ws_client_num, ControllerState* out) const {
  if (out == nullptr) {
    return false;
  }
  const int8_t slot_index = findSlotByWsClient(ws_client_num);
  if (slot_index < 0) {
    return false;
  }
  *out = slots_[slot_index].state;
  return true;
}

bool ControllerSessionManager::applyStateForClient(uint8_t ws_client_num, const ControllerState& next, uint32_t now_ms) {
  const int8_t slot_index = findSlotByWsClient(ws_client_num);
  if (slot_index < 0) {
    return false;
  }

  SlotRecord& slot = slots_[slot_index];
  if (!slot.connected || !slot.assigned || next.seq <= slot.state.seq) {
    return false;
  }

  slot.state = next;
  slot.state.last_update_ms = now_ms;
  slot.last_packet_ms = now_ms;
  return true;
}

bool ControllerSessionManager::disconnectClient(uint8_t ws_client_num, uint32_t now_ms) {
  const int8_t slot_index = findSlotByWsClient(ws_client_num);
  if (slot_index < 0) {
    return false;
  }
  terminateSlot(static_cast<uint8_t>(slot_index), now_ms);
  return true;
}

uint8_t ControllerSessionManager::collectTimedOutClients(uint32_t now_ms, uint8_t* out_ws_clients, uint8_t max_out) {
  uint8_t count = 0;
  for (uint8_t i = 0; i < capacity_; ++i) {
    SlotRecord& slot = slots_[i];
    if (!slot.assigned || !slot.connected || slot.ws_client_num == kUnboundWsClient) {
      continue;
    }
    if (slot.last_packet_ms == 0 || now_ms - slot.last_packet_ms <= config::kWsTimeoutMs) {
      continue;
    }
    if (out_ws_clients != nullptr && count < max_out) {
      out_ws_clients[count] = slot.ws_client_num;
    }
    ++count;
    terminateSlot(i, now_ms);
  }
  return count;
}

void ControllerSessionManager::evictExpiredReservations(uint32_t now_ms) {
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    if (slots_[i].assigned && !slots_[i].connected && reservationExpired(slots_[i], now_ms)) {
      clearSlot(i);
    }
  }
}

void ControllerSessionManager::resetAllStates() {
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    slots_[i].state = ControllerState{};
    if (slots_[i].connected) {
      slots_[i].last_packet_ms = 0;
    }
  }
}

ControllerFleetSnapshot ControllerSessionManager::snapshot(uint32_t now_ms) const {
  ControllerFleetSnapshot fleet;
  fleet.max_slots = capacity_;
  for (uint8_t i = 0; i < config::kMaxControllerSlots; ++i) {
    ControllerSlotSnapshot& snapshot_slot = fleet.slots[i];
    snapshot_slot.slot_number = static_cast<uint8_t>(i + 1);
    if (i >= capacity_) {
      continue;
    }

    const SlotRecord& slot = slots_[i];
    snapshot_slot.assigned = slot.assigned;
    snapshot_slot.connected = slot.connected;
    snapshot_slot.reserved = slot.assigned && !slot.connected && !reservationExpired(slot, now_ms);
    snapshot_slot.active = slot.assigned && slot.connected;
    snapshot_slot.state = slot.state;
    snapshot_slot.last_packet_age_ms = slot.connected && slot.last_packet_ms > 0 ? now_ms - slot.last_packet_ms : 0;

    if (snapshot_slot.assigned) {
      ++fleet.assigned_slots;
    }
    if (snapshot_slot.connected) {
      ++fleet.connected_slots;
      fleet.ws_connected = true;
      ++fleet.active_slots;
      fleet.active_slot_mask |= (1u << i);
    }
  }
  return fleet;
}

int8_t ControllerSessionManager::findSlotByWsClient(uint8_t ws_client_num) const {
  for (uint8_t i = 0; i < capacity_; ++i) {
    if (slots_[i].assigned && slots_[i].connected && slots_[i].ws_client_num == ws_client_num) {
      return static_cast<int8_t>(i);
    }
  }
  return -1;
}

int8_t ControllerSessionManager::findSlotByClientId(const char* client_id) const {
  for (uint8_t i = 0; i < capacity_; ++i) {
    if (slots_[i].assigned && strcmp(slots_[i].client_id, client_id) == 0) {
      return static_cast<int8_t>(i);
    }
  }
  return -1;
}

int8_t ControllerSessionManager::findFreeSlot(uint32_t now_ms) const {
  for (uint8_t i = 0; i < capacity_; ++i) {
    if (!slots_[i].assigned) {
      return static_cast<int8_t>(i);
    }
    if (!slots_[i].connected && reservationExpired(slots_[i], now_ms)) {
      return static_cast<int8_t>(i);
    }
  }
  return -1;
}

bool ControllerSessionManager::reservationExpired(const SlotRecord& slot, uint32_t now_ms) const {
  return !slot.connected && slot.grace_deadline_ms > 0 &&
         static_cast<int32_t>(now_ms - slot.grace_deadline_ms) >= 0;
}

void ControllerSessionManager::clearSlot(uint8_t slot_index) {
  slots_[slot_index] = SlotRecord{};
}

void ControllerSessionManager::terminateSlot(uint8_t slot_index, uint32_t now_ms) {
  SlotRecord& slot = slots_[slot_index];
  if (!slot.assigned) {
    return;
  }
  slot.connected = false;
  slot.ws_client_num = kUnboundWsClient;
  slot.last_packet_ms = 0;
  slot.grace_deadline_ms = now_ms + config::kControllerReconnectGraceMs;
  slot.state = ControllerState{};
}
