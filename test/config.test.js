const assert = require('node:assert/strict');
const { validateAlphabet, loadConfig, DEFAULT_CONFIG } = require('../src/claude-vimium.js');

// valid
assert.deepEqual(validateAlphabet('asdfgqwertzxcv'), { ok: true });

// reserved keys are rejected, and the reason names the offending character
{
  const result = validateAlphabet('asdfj');
  assert.equal(result.ok, false);
  assert.match(result.reason, /j/);
}

// duplicates and empties
assert.equal(validateAlphabet('aab').ok, false);
assert.equal(validateAlphabet('').ok, false);

// single character cannot address more than one target
assert.equal(validateAlphabet('a').ok, false);

// loadConfig falls back on garbage rather than throwing
assert.deepEqual(loadConfig(null), DEFAULT_CONFIG);
assert.deepEqual(loadConfig('not json'), DEFAULT_CONFIG);
assert.deepEqual(loadConfig('{"alphabet":"hjkl"}').alphabet, DEFAULT_CONFIG.alphabet);
assert.deepEqual(loadConfig('{"scrollAmount":-5}').scrollAmount, DEFAULT_CONFIG.scrollAmount);

// valid overrides survive
{
  const loaded = loadConfig('{"alphabet":"asdf","scrollAmount":120}');
  assert.equal(loaded.alphabet, 'asdf');
  assert.equal(loaded.scrollAmount, 120);
}

console.log('config.test.js OK');
