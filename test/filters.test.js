const assert = require('node:assert/strict');
const { passesGeometry, passesStyle, orderByScreenPosition, latinChar, resolveHintChar } = require('../src/claude-vimium.js');

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

// orderByScreenPosition: overlap-based row clustering
const entry = (key, o) => ({ key, rect: rect(o) });

// Reviewer's repro: elements 2px apart vertically should be same row, ordered by left
const sameRowResult = orderByScreenPosition([
  entry('far-right', { top: 9, left: 900, bottom: 20 }),
  entry('near-left', { top: 11, left: 10, bottom: 22 }),
]);
assert.equal(sameRowResult[0].key, 'near-left', 'overlapping vertically, ordered by left');
assert.equal(sameRowResult[1].key, 'far-right');

// Two clearly separate rows order top-first regardless of left values
const separateRowsResult = orderByScreenPosition([
  entry('top-row-right', { top: 50, left: 900, bottom: 60 }),
  entry('bot-row-left', { top: 100, left: 10, bottom: 110 }),
]);
assert.equal(separateRowsResult[0].key, 'top-row-right', 'separate rows, ordered top-first');
assert.equal(separateRowsResult[1].key, 'bot-row-left');

// Three elements on one row in left-to-right order
const oneRowResult = orderByScreenPosition([
  entry('c', { top: 50, left: 300, bottom: 60 }),
  entry('a', { top: 50, left: 100, bottom: 60 }),
  entry('b', { top: 50, left: 200, bottom: 60 }),
]);
assert.equal(oneRowResult[0].key, 'a');
assert.equal(oneRowResult[1].key, 'b');
assert.equal(oneRowResult[2].key, 'c');

// Tall element does not absorb rows below: tall opening element then a separate row
const tallElemResult = orderByScreenPosition([
  entry('tall', { top: 50, left: 100, bottom: 150 }),
  entry('separate', { top: 160, left: 200, bottom: 170 }),
]);
assert.equal(tallElemResult[0].key, 'tall', 'tall element opens its row');
assert.equal(tallElemResult[1].key, 'separate', 'separate row starts above tall element bottom');

// ── resolveHintChar ──────────────────────────────────────────────

const ALPHA = 'asfgqwertzxcv';

// Latin keyboard: the logical key is in the alphabet and wins.
assert.equal(resolveHintChar({ key: 'a', code: 'KeyA' }, ALPHA), 'a');
assert.equal(resolveHintChar({ key: 'S', code: 'KeyS' }, ALPHA), 's');

// Korean IME: the logical key is a jamo, so the physical key decides.
assert.equal(resolveHintChar({ key: 'ㅁ', code: 'KeyA' }, ALPHA), 'a');
assert.equal(resolveHintChar({ key: 'ㄴ', code: 'KeyS' }, ALPHA), 's');

// A physical key outside the alphabet stays unmatched even via fallback.
assert.equal(resolveHintChar({ key: 'ㅏ', code: 'KeyK' }, ALPHA), null);

// Reserved navigation keys must never resolve to a hint character.
assert.equal(resolveHintChar({ key: 'j', code: 'KeyJ' }, ALPHA), null);
assert.equal(resolveHintChar({ key: 'h', code: 'KeyH' }, ALPHA), null);

// d and u are scroll commands now, so they never resolve as hint characters.
assert.equal(resolveHintChar({ key: 'd', code: 'KeyD' }, ALPHA), null);
assert.equal(resolveHintChar({ key: 'u', code: 'KeyU' }, ALPHA), null);

// Non-character keys and missing fields.
assert.equal(resolveHintChar({ key: 'Enter', code: 'Enter' }, ALPHA), null);
assert.equal(resolveHintChar({ key: 'Backspace', code: 'Backspace' }, ALPHA), null);
assert.equal(resolveHintChar({ key: '', code: '' }, ALPHA), null);
assert.equal(resolveHintChar({}, ALPHA), null);

// A custom alphabet changes what resolves.
assert.equal(resolveHintChar({ key: 'ㅁ', code: 'KeyA' }, 'xyz'), null);
assert.equal(resolveHintChar({ key: 'ㅋ', code: 'KeyZ' }, 'xyz'), 'z');

// Modifier chords belong to the app, not to label matching.
assert.equal(resolveHintChar({ key: 'v', code: 'KeyV', metaKey: true }, ALPHA), null);
assert.equal(resolveHintChar({ key: 'c', code: 'KeyC', ctrlKey: true }, ALPHA), null);
assert.equal(resolveHintChar({ key: 'a', code: 'KeyA', altKey: true }, ALPHA), null);
// Shift still resolves — it is how capitals are typed.
assert.equal(resolveHintChar({ key: 'A', code: 'KeyA', shiftKey: true }, ALPHA), 'a');
// Plain keys are unaffected.
assert.equal(resolveHintChar({ key: 'v', code: 'KeyV' }, ALPHA), 'v');

// ── latinChar ────────────────────────────────────────────────────

// Latin keyboard: the logical key is already a letter.
assert.equal(latinChar({ key: 'j', code: 'KeyJ' }), 'j');
assert.equal(latinChar({ key: 'K', code: 'KeyK' }), 'k');

// Korean IME: the logical key is a jamo, so the physical key decides.
assert.equal(latinChar({ key: 'ㅓ', code: 'KeyJ' }), 'j');
assert.equal(latinChar({ key: 'ㅏ', code: 'KeyK' }), 'k');
assert.equal(latinChar({ key: 'ㅁ', code: 'KeyA' }), 'a');

// Non-letter keys resolve to nothing, even when they carry a code.
assert.equal(latinChar({ key: 'ArrowDown', code: 'ArrowDown' }), null);
assert.equal(latinChar({ key: 'Home', code: 'Home' }), null);
assert.equal(latinChar({ key: '1', code: 'Digit1' }), null);
assert.equal(latinChar({ key: ';', code: 'Semicolon' }), null);

// Missing fields.
assert.equal(latinChar({}), null);
assert.equal(latinChar({ key: '', code: '' }), null);

console.log('filters.test.js OK');
