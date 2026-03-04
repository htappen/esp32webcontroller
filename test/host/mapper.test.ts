import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

function toAxis(v: number): number {
  const clamped = Math.max(-1, Math.min(1, v));
  return Math.trunc(clamped * 32767);
}

describe('mapper math', () => {
  it('clamps axis into signed 16-bit range', () => {
    assert.equal(toAxis(2), 32767);
    assert.equal(toAxis(-2), -32767);
    assert.equal(toAxis(0.5), 16383);
  });
});
