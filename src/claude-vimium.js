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

  function passesGeometry(rect, viewport) {
    if (rect.width === 0 || rect.height === 0) return false;
    if (rect.bottom <= 0 || rect.top >= viewport.height) return false;
    if (rect.right <= 0 || rect.left >= viewport.width) return false;
    return true;
  }

  function passesStyle(style) {
    if (style.display === 'none') return false;
    if (style.visibility === 'hidden') return false;
    if (parseFloat(style.opacity) < 0.01) return false;
    return true;
  }

  // ─── Node test export ────────────────────────────────────────────

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { generateLabels, passesGeometry, passesStyle };
    return; // no DOM in Node; stop before init
  }

  // ─── runtime ─────────────────────────────────────────────────────

  const HINT_SELECTOR = [
    'button',
    'a[href]',
    'input',
    'textarea',
    'select',
    '[role="button"]',
    '[role="menuitem"]',
    '[role="tab"]',
    '[role="link"]',
    '[tabindex]:not([tabindex="-1"])',
    '[contenteditable="true"]',
  ].join(',');

  function collectTargets() {
    const viewport = { width: window.innerWidth, height: window.innerHeight };
    const visible = [...document.querySelectorAll(HINT_SELECTOR)].filter((el) => {
      if (el.disabled) return false;
      if (el.closest('#claude-vimium-overlay')) return false;
      if (!passesGeometry(el.getBoundingClientRect(), viewport)) return false;
      return passesStyle(getComputedStyle(el));
    });

    // Keep only the innermost candidate when candidates nest inside one another.
    const innermost = visible.filter(
      (el) => !visible.some((other) => other !== el && el.contains(other)),
    );

    // Screen order: top to bottom, then left to right. Rows are bucketed so
    // that elements on the same visual row are not reordered by sub-pixel
    // differences in their top coordinate.
    return innermost.sort((a, b) => {
      const ra = a.getBoundingClientRect();
      const rb = b.getBoundingClientRect();
      const rowA = Math.round(ra.top / 20);
      const rowB = Math.round(rb.top / 20);
      return rowA - rowB || ra.left - rb.left;
    });
  }

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

    window.__claudeVimium = { teardown, on, collectTargets };
    console.log('[claude-vimium] ready');
  }

  init();
})();
