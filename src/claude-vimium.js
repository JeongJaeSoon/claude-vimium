// claude-vimium — keyboard-driven UI navigation for Claude Desktop
// Injected into Claude.app's ion-dist bundle. No dependencies, no build step.
(() => {
  'use strict';

  // ─── pure helpers (tested from Node) ─────────────────────────────

  // Assign the shortest possible labels without any label prefixing another.
  // Single-character labels are handed out first, in the order the caller
  // supplies (callers pass candidates in screen order so the top-left
  // element gets the cheapest key).
  function generateLabels(count, alphabet) {
    if (!alphabet) throw new Error('generateLabels: alphabet must not be empty');
    if (count <= 0) return [];

    const n = alphabet.length;
    const capacity = n * n;
    const total = Math.min(count, capacity);

    if (total <= n) return alphabet.slice(0, total).split('');

    // Maximize the number of single-char labels s such that the remaining
    // (n - s) prefixes still cover the rest: s + (n - s) * n >= total.
    const single = n > 1 ? Math.max(0, Math.floor((capacity - total) / (n - 1))) : 0;

    const labels = alphabet.slice(0, single).split('');
    for (let i = single; i < n && labels.length < total; i++) {
      for (let j = 0; j < n && labels.length < total; j++) {
        labels.push(alphabet[i] + alphabet[j]);
      }
    }
    return labels;
  }

  // ─── Node test export ────────────────────────────────────────────

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { generateLabels };
    return; // no DOM in Node; stop before init
  }

  // ─── runtime ─────────────────────────────────────────────────────

  function init() {
    // Re-running this file must not leave a second instance behind.
    if (window.__claudeVimium) window.__claudeVimium.teardown();

    const listeners = [];
    const on = (target, type, fn, opts) => {
      target.addEventListener(type, fn, opts);
      listeners.push(() => target.removeEventListener(type, fn, opts));
    };

    function teardown() {
      listeners.forEach((off) => off());
      listeners.length = 0;
      delete window.__claudeVimium;
    }

    window.__claudeVimium = { teardown, on };
    console.log('[claude-vimium] ready');
  }

  init();
})();
