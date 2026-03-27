#include "state_store.h"

bool StateStore::reset() {
  const bool changed = state_.seq != 0 || state_.t != 0 || state_.last_update_ms != 0 ||
                       state_.btn.a || state_.btn.b || state_.btn.x || state_.btn.y || state_.btn.lb ||
                       state_.btn.rb || state_.btn.back || state_.btn.start || state_.btn.ls ||
                       state_.btn.rs || state_.btn.du || state_.btn.dd || state_.btn.dl ||
                       state_.btn.dr || state_.ax.lx != 0.0f || state_.ax.ly != 0.0f ||
                       state_.ax.rx != 0.0f || state_.ax.ry != 0.0f || state_.ax.lt != 0.0f ||
                       state_.ax.rt != 0.0f;
  state_ = ControllerState{};
  return changed;
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
