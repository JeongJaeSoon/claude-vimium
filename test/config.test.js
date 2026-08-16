const assert = require('node:assert/strict');
const { validateAlphabet, validateLeader, loadConfig, DEFAULT_CONFIG } = require('../src/claude-vimium.js');

// valid
assert.deepEqual(validateAlphabet('asfgqwertzxcv'), { ok: true });

// reserved keys are rejected, and the reason names the offending character
{
  const result = validateAlphabet('asfgj');
  assert.equal(result.ok, false);
  assert.match(result.reason, /j/);
}

// duplicates and empties
assert.equal(validateAlphabet('aab').ok, false);
assert.equal(validateAlphabet('').ok, false);

// single character cannot address more than one target
assert.equal(validateAlphabet('a').ok, false);

// Every reserved key is rejected, wherever it sits in the string.
for (const ch of ['h', 'j', 'k', 'l', 'd', 'u', ',', '?']) {
  assert.equal(validateAlphabet(ch + 'asdf').ok, false, `leading ${ch}`);
  assert.equal(validateAlphabet('as' + ch + 'df').ok, false, `middle ${ch}`);
  assert.equal(validateAlphabet('asdf' + ch).ok, false, `trailing ${ch}`);
}

// d and u became reserved when they gained half-page scrolling.
assert.equal(validateAlphabet('asfgd').ok, false);
assert.equal(validateAlphabet('asfgu').ok, false);

// DEFAULT_CONFIG.alphabet must pass its own validation.
assert.equal(DEFAULT_CONFIG.alphabet, 'asfgqwertzxcv');
assert.equal(validateAlphabet(DEFAULT_CONFIG.alphabet).ok, true);

// loadConfig falls back on garbage rather than throwing
assert.deepEqual(loadConfig(null), DEFAULT_CONFIG);
assert.deepEqual(loadConfig('not json'), DEFAULT_CONFIG);
assert.deepEqual(loadConfig('{"alphabet":"hjkl"}').alphabet, DEFAULT_CONFIG.alphabet);
assert.deepEqual(loadConfig('{"scrollAmount":-5}').scrollAmount, DEFAULT_CONFIG.scrollAmount);

// valid overrides survive
{
  const loaded = loadConfig('{"alphabet":"asfg","scrollAmount":120}');
  assert.equal(loaded.alphabet, 'asfg');
  assert.equal(loaded.scrollAmount, 120);
}

// ── validateLeader ───────────────────────────────────────────────

assert.deepEqual(validateLeader({ key: ';', ctrl: true }), { ok: true });
assert.deepEqual(validateLeader({ key: 'k', meta: true }), { ok: true });
assert.deepEqual(validateLeader({ key: 'F1', alt: true }), { ok: true });

// A bare key would fire on every keystroke and lock the user out.
assert.equal(validateLeader({ key: 'h' }).ok, false);
assert.equal(validateLeader({ key: 'a', shift: true }).ok, false);

// Malformed input.
assert.equal(validateLeader({ key: '', ctrl: true }).ok, false);
assert.equal(validateLeader({}).ok, false);
assert.equal(validateLeader(null).ok, false);

// loadConfig must refuse a hand-edited bare leader and keep the default.
assert.deepEqual(
  loadConfig('{"leader":{"key":"h"}}').leader,
  DEFAULT_CONFIG.leader,
);

console.log('config.test.js OK');
