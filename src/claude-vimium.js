// claude-vimium — keyboard-driven UI navigation for Claude Desktop
// Injected into Claude.app's ion-dist bundle. No dependencies, no build step.
(() => {
  'use strict';

  // ─── pure helpers (tested from Node) ─────────────────────────────

  // Which hint character did this keystroke mean?
  //
  // Prefer the logical key: on a Dvorak or AZERTY layout the label on screen
  // matches what `key` reports, and the physical key does not.
  //
  // Fall back to the physical key only when the logical one is not in the
  // alphabet at all. That is the Korean/Japanese case: the IME reports a
  // composed jamo ('ㅁ') for the key printed 'a', so matching on `key` can
  // never succeed no matter what the user presses.
  function resolveHintChar(event, alphabet) {
    const logical = typeof event.key === 'string' ? event.key.toLowerCase() : '';
    if (logical.length === 1 && alphabet.includes(logical)) return logical;

    const physical = /^Key([A-Z])$/.exec(event.code || '');
    if (physical) {
      const ch = physical[1].toLowerCase();
      if (alphabet.includes(ch)) return ch;
    }
    return null;
  }

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

  // Group entries into visual rows, then order each row left to right.
  // Rows are found by vertical overlap rather than a fixed grid: a grid
  // splits same-row elements whenever they straddle a bucket boundary.
  function orderByScreenPosition(entries) {
    const sorted = [...entries].sort((a, b) => a.rect.top - b.rect.top);
    const rows = [];
    for (const entry of sorted) {
      const row = rows[rows.length - 1];
      if (row && entry.rect.top < row.bottom) {
        row.items.push(entry);
      } else {
        // The row's band is set by the element that opened it. Widening it
        // to each new member would let one tall element swallow the rows
        // below it.
        rows.push({ items: [entry], bottom: entry.rect.bottom });
      }
    }
    return rows.flatMap((row) => row.items.sort((a, b) => a.rect.left - b.rect.left));
  }

  // ─── Node test export ────────────────────────────────────────────

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { generateLabels, resolveHintChar, passesGeometry, passesStyle, orderByScreenPosition };
    return; // no DOM in Node; stop before init
  }

  // ─── runtime ─────────────────────────────────────────────────────

  const config = {
    leader: { key: ';', ctrl: true, meta: false, alt: false, shift: false },
    alphabet: 'asdfgqwertzxcv',
    scrollAmount: 60,
  };

  let toastTimer = null;
  function toast(message) {
    const overlay = ensureOverlay();
    let el = overlay.querySelector('[data-cv-toast]');
    if (!el) {
      el = document.createElement('div');
      el.dataset.cvToast = '';
      el.style.cssText = [
        'position:fixed',
        'bottom:24px',
        'left:50%',
        'transform:translateX(-50%)',
        'padding:6px 12px',
        'border-radius:6px',
        'background:rgba(0,0,0,.85)',
        'color:#fff',
        'font:500 12px/1.3 system-ui,sans-serif',
      ].join(';');
      overlay.appendChild(el);
    }
    el.textContent = message;
    el.style.display = '';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.style.display = 'none'; }, 1600);
  }

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

  const OVERLAY_ID = 'claude-vimium-overlay';
  const hintState = { active: false, entries: [], typed: '' };
  let overlayEl = null;
  let repositionQueued = false;
  let observer = null;
  let previousFocus = null;

  function ensureOverlay() {
    if (overlayEl && overlayEl.isConnected) return overlayEl;
    overlayEl = document.createElement('div');
    overlayEl.id = OVERLAY_ID;
    overlayEl.style.cssText = [
      'position:fixed',
      'inset:0',
      'z-index:2147483647',
      'pointer-events:none',
      'font:600 11px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace',
    ].join(';');
    document.body.appendChild(overlayEl);
    return overlayEl;
  }

  function makeLabelNode(label) {
    const node = document.createElement('div');
    node.style.cssText = [
      'position:fixed',
      'padding:1px 3px',
      'border-radius:3px',
      'background:#ffd400',
      'color:#000',
      'box-shadow:0 1px 3px rgba(0,0,0,.4)',
      'white-space:nowrap',
    ].join(';');

    const typed = document.createElement('span');
    typed.dataset.cvTyped = '';
    typed.style.color = 'rgba(0,0,0,.35)';

    const rest = document.createElement('span');
    rest.dataset.cvRest = '';
    rest.textContent = label;

    node.append(typed, rest);
    return node;
  }

  // Nudge labels that would sit on top of each other. Dense toolbars put
  // several targets within a few pixels; without this the labels are
  // unreadable exactly where hints matter most.
  function placeLabels() {
    const taken = [];
    for (const entry of hintState.entries) {
      if (entry.node.style.display === 'none') continue;
      const r = entry.el.getBoundingClientRect();
      let top = r.top;
      let left = r.left;
      while (taken.some((t) => Math.abs(t.top - top) < 12 && Math.abs(t.left - left) < 18)) {
        left += 14;
        if (left > r.right + 28) {
          left = r.left;
          top += 12;
        }
      }
      taken.push({ top, left });
      entry.node.style.top = `${Math.max(0, top)}px`;
      entry.node.style.left = `${Math.max(0, left)}px`;
    }
  }

  function queueReposition() {
    if (repositionQueued) return;
    repositionQueued = true;
    requestAnimationFrame(() => {
      repositionQueued = false;
      if (!hintState.active) return;
      // Drop entries whose element left the DOM, then re-place the rest.
      for (const entry of hintState.entries) {
        if (!entry.el.isConnected) entry.node.style.display = 'none';
      }
      placeLabels();
    });
  }

  function showHints() {
    hideHints();

    const targets = collectTargets();
    if (targets.length === 0) {
      toast('힌트 대상 없음');
      return;
    }

    // Leave the composer only once we know hints will be drawn. Blurring
    // before this check would strand the user with no focus and no hint mode
    // to escape from. macOS's Korean IME starts a composition on the first
    // hint keystroke even though we preventDefault it, and every keystroke
    // after that arrives with isComposing set — with nothing focused there is
    // nothing to compose into.
    previousFocus = document.activeElement;
    if (previousFocus && previousFocus !== document.body && typeof previousFocus.blur === 'function') {
      previousFocus.blur();
    } else {
      previousFocus = null;
    }

    const labels = generateLabels(targets.length, config.alphabet);
    const overlay = ensureOverlay();
    hintState.entries = labels.map((label, i) => {
      const node = makeLabelNode(label);
      overlay.appendChild(node);
      return { el: targets[i], label, node };
    });
    hintState.active = true;
    hintState.typed = '';
    placeLabels();

    window.addEventListener('scroll', queueReposition, true);
    window.addEventListener('resize', queueReposition);
    observer = new MutationObserver(queueReposition);
    observer.observe(document.body, { childList: true, subtree: true });
  }

  function hideHints() {
    hintState.active = false;
    hintState.entries = [];
    hintState.typed = '';
    if (overlayEl) overlayEl.replaceChildren();
    window.removeEventListener('scroll', queueReposition, true);
    window.removeEventListener('resize', queueReposition);
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    if (previousFocus && previousFocus.isConnected && typeof previousFocus.focus === 'function') {
      previousFocus.focus();
    }
    previousFocus = null;
  }

  function filterHints(typed) {
    for (const entry of hintState.entries) {
      const match = entry.label.startsWith(typed);
      entry.node.style.display = match ? '' : 'none';
      if (!match) continue;
      entry.node.querySelector('[data-cv-typed]').textContent = entry.label.slice(0, typed.length);
      entry.node.querySelector('[data-cv-rest]').textContent = entry.label.slice(typed.length);
    }
    placeLabels();
  }

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

    const entries = innermost.map((el) => ({ el, rect: el.getBoundingClientRect() }));
    return orderByScreenPosition(entries).map((entry) => entry.el);
  }

  const RESERVED_KEYS = ['h', 'j', 'k', 'l', ',', '?'];
  const FOCUSABLE_INPUT = 'input,textarea,[contenteditable="true"]';

  function matchesLeader(e) {
    const l = config.leader;
    return (
      e.key === l.key &&
      e.ctrlKey === !!l.ctrl &&
      e.metaKey === !!l.meta &&
      e.altKey === !!l.alt &&
      e.shiftKey === !!l.shift
    );
  }

  function activate(el) {
    if (!el.isConnected) return;
    if (el.matches(FOCUSABLE_INPUT)) {
      el.focus();
      return;
    }
    el.click();
  }

  function flashNoMatch() {
    const overlay = ensureOverlay();
    overlay.animate(
      [{ transform: 'translateX(0)' }, { transform: 'translateX(3px)' },
       { transform: 'translateX(-3px)' }, { transform: 'translateX(0)' }],
      { duration: 120 },
    );
  }

  function onKeyDown(e) {
    // While the user is typing, an IME composition must never be touched —
    // intercepting it corrupts the syllable being assembled.
    //
    // Hint mode is the opposite case. We blur the focused element on entry,
    // so nothing can legitimately be composing; if the IME still reports a
    // composition or keyCode 229, honoring it would swallow the keystroke and
    // let it fall through to the app. That is the bug this replaces.
    if (!hintState.active && (e.isComposing || e.keyCode === 229)) return;

    if (!hintState.active) {
      if (matchesLeader(e)) {
        e.preventDefault();
        e.stopPropagation();
        showHints();
      }
      return;
    }

    // From here on the mode is active and every key belongs to us.
    e.preventDefault();
    e.stopPropagation();

    if (e.key === 'Escape' || matchesLeader(e)) {
      hideHints();
      return;
    }

    if (e.key === 'Backspace') {
      // Nothing typed yet — there is nothing to undo, so treat it as "leave".
      if (!hintState.typed) {
        hideHints();
        return;
      }
      hintState.typed = hintState.typed.slice(0, -1);
      filterHints(hintState.typed);
      return;
    }

    const char = resolveHintChar(e, config.alphabet);
    if (!char) return;

    const next = hintState.typed + char;
    const matches = hintState.entries.filter((entry) => entry.label.startsWith(next));

    if (matches.length === 0) {
      flashNoMatch();
      return;
    }

    const exact = matches.find((entry) => entry.label === next);
    if (exact && matches.length === 1) {
      const { el } = exact;
      hideHints();
      activate(el);
      return;
    }

    hintState.typed = next;
    filterHints(next);
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
      hideHints();
      listeners.forEach((off) => off());
      listeners.length = 0;
      delete window.__claudeVimium;
    }

    on(window, 'keydown', onKeyDown, true);

    window.__claudeVimium = { teardown, on, collectTargets, showHints, hideHints, hintState };
    console.log('[claude-vimium] ready');
  }

  init();
})();
