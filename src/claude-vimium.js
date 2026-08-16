// claude-vimium — keyboard-driven UI navigation for Claude Desktop
// Injected into Claude.app's ion-dist bundle. No dependencies, no build step.
(() => {
  'use strict';

  // ─── pure helpers (tested from Node) ─────────────────────────────

  // (filled in by later tasks)

  // ─── Node test export ────────────────────────────────────────────

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {};
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
