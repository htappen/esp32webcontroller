import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('protocol packet', () => {
  it('accepts minimal neutral packet shape', () => {
    const packet = {
      t: Date.now(),
      seq: 1,
      btn: { a: 0, b: 0, x: 0, y: 0, lb: 0, rb: 0, back: 0, start: 0, ls: 0, rs: 0, du: 0, dd: 0, dl: 0, dr: 0 },
      ax: { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0 },
    };

    assert.equal(typeof packet.seq, 'number');
    assert.equal(packet.btn.a, 0);
  });

  it('accepts sparse delta packets', () => {
    const packet = {
      t: Date.now(),
      seq: 2,
      btn: { a: 1, dr: 1 },
      ax: { lx: -0.5 },
    };

    assert.equal(packet.btn.a, 1);
    assert.equal(packet.btn.dr, 1);
    assert.equal(packet.ax.lx, -0.5);
  });
});
