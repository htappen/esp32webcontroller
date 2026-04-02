export const BUTTON_KEYS = ['a', 'b', 'x', 'y', 'lb', 'rb', 'back', 'start', 'ls', 'rs', 'du', 'dd', 'dl', 'dr'];
export const AXIS_KEYS = ['lx', 'ly', 'rx', 'ry', 'lt', 'rt'];
export const BUTTON_INDEX_TO_KEY = Object.freeze({
  0: 'a',
  1: 'b',
  2: 'x',
  3: 'y',
  4: 'lb',
  5: 'rb',
  8: 'back',
  9: 'start',
  10: 'ls',
  11: 'rs',
  12: 'du',
  13: 'dd',
  14: 'dl',
  15: 'dr',
});
export const AXIS_INDEX_TO_KEY = Object.freeze({
  0: 'lx',
  1: 'ly',
  2: 'rx',
  3: 'ry',
});
export const TRIGGER_BUTTON_INDEX_TO_AXIS_KEY = Object.freeze({
  6: 'lt',
  7: 'rt',
});
export const FULL_STATE_INTERVAL_MS = 1000;

export function createNeutralControllerState() {
  return {
    t: 0,
    seq: 0,
    btn: Object.fromEntries(BUTTON_KEYS.map((key) => [key, 0])),
    ax: Object.fromEntries(AXIS_KEYS.map((key) => [key, 0])),
  };
}
