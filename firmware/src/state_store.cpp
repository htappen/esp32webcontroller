#include "state_store.h"

void StateStore::reset() {
  state_ = ControllerState{};
}

bool StateStore::apply(const ControllerState& next) {
  if (next.seq <= state_.seq) {
    return false;
  }
  state_ = next;
  return true;
}

ControllerState StateStore::snapshot() const {
  return state_;
}
