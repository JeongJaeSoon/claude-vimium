const assert = require('node:assert/strict');
const { generateLabels } = require('../src/claude-vimium.js');

function noPrefixCollision(labels) {
  return labels.every((a) => labels.every((b) => a === b || !b.startsWith(a)));
}

// count <= alphabet size: all single characters
{
  const labels = generateLabels(3, 'abcd');
  assert.deepEqual(labels, ['a', 'b', 'c']);
}

// exactly alphabet size
{
  const labels = generateLabels(4, 'abcd');
  assert.deepEqual(labels, ['a', 'b', 'c', 'd']);
}

// overflow into two characters, still prefix-free
{
  const labels = generateLabels(6, 'abcd');
  assert.equal(labels.length, 6);
  assert.ok(noPrefixCollision(labels), 'labels must be prefix-free');
  assert.equal(new Set(labels).size, 6, 'labels must be unique');
}

// default alphabet, realistic count
{
  const labels = generateLabels(40, 'asdfgqwertzxcv');
  assert.equal(labels.length, 40);
  assert.ok(noPrefixCollision(labels), 'labels must be prefix-free');
  assert.equal(new Set(labels).size, 40, 'labels must be unique');
}

// beyond two-character capacity: cap at alphabet^2, do not throw
{
  const labels = generateLabels(500, 'abcd');
  assert.equal(labels.length, 16);
  assert.ok(noPrefixCollision(labels), 'labels must be prefix-free');
}

// degenerate input
{
  assert.deepEqual(generateLabels(0, 'abcd'), []);
  assert.throws(() => generateLabels(3, ''), /alphabet/);
}

console.log('labels.test.js OK');
