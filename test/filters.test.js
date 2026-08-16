const assert = require('node:assert/strict');
const { passesGeometry, passesStyle } = require('../src/claude-vimium.js');

const VIEWPORT = { width: 1000, height: 800 };
const rect = (o) => ({
  top: 0, left: 0, width: 10, height: 10,
  bottom: 10, right: 10, ...o,
});

// fully visible
assert.equal(passesGeometry(rect({}), VIEWPORT), true);

// zero-sized
assert.equal(passesGeometry(rect({ width: 0, right: 0 }), VIEWPORT), false);
assert.equal(passesGeometry(rect({ height: 0, bottom: 0 }), VIEWPORT), false);

// entirely above / below / left / right of the viewport
assert.equal(passesGeometry(rect({ top: -50, bottom: -40 }), VIEWPORT), false);
assert.equal(passesGeometry(rect({ top: 900, bottom: 910 }), VIEWPORT), false);
assert.equal(passesGeometry(rect({ left: -50, right: -40 }), VIEWPORT), false);
assert.equal(passesGeometry(rect({ left: 1100, right: 1110 }), VIEWPORT), false);

// partially visible counts as visible
assert.equal(passesGeometry(rect({ top: -5, bottom: 5 }), VIEWPORT), true);

// style
assert.equal(passesStyle({ display: 'block', visibility: 'visible', opacity: '1' }), true);
assert.equal(passesStyle({ display: 'none', visibility: 'visible', opacity: '1' }), false);
assert.equal(passesStyle({ display: 'block', visibility: 'hidden', opacity: '1' }), false);
assert.equal(passesStyle({ display: 'block', visibility: 'visible', opacity: '0' }), false);

// near-zero opacity is still invisible in practice
assert.equal(passesStyle({ display: 'block', visibility: 'visible', opacity: '0.001' }), false);

console.log('filters.test.js OK');
