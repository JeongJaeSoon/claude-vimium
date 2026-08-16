// claude-vimium — keyboard-driven UI navigation for Claude Desktop
// Injected into Claude.app's ion-dist bundle. No dependencies, no build step.
(() => {
  'use strict';

  // ─── pure helpers (tested from Node) ─────────────────────────────

  // The latin letter this keystroke lands on, whatever the input method.
  //
  // Prefer the logical key: on Dvorak or AZERTY the letter printed on the cap
  // is what `key` reports, and the physical key is not.
  //
  // Fall back to the physical key when the logical one is not a latin letter
  // at all. That is the Korean/Japanese case — the IME reports a composed
  // jamo ('ㅓ') for the key printed 'j', so matching on `key` can never
  // succeed no matter what the user presses.
  function latinChar(event) {
    const logical = typeof event.key === 'string' ? event.key.toLowerCase() : '';
    if (/^[a-z]$/.test(logical)) return logical;

    const physical = /^Key([A-Z])$/.exec(event.code || '');
    return physical ? physical[1].toLowerCase() : null;
  }

  function resolveHintChar(event, alphabet) {
    const ch = latinChar(event);
    return ch && alphabet.includes(ch) ? ch : null;
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

  const RESERVED_KEYS = ['h', 'j', 'k', 'l', ',', '?'];

  const DEFAULT_CONFIG = {
    leader: { key: ';', ctrl: true, meta: false, alt: false, shift: false },
    alphabet: 'asdfgqwertzxcv',
    scrollAmount: 60,
  };

  function validateAlphabet(alphabet) {
    if (typeof alphabet !== 'string' || alphabet.length < 2) {
      return { ok: false, reason: '문자셋은 2글자 이상이어야 합니다' };
    }
    if (new Set(alphabet).size !== alphabet.length) {
      return { ok: false, reason: '중복된 문자가 있습니다' };
    }
    const clash = [...alphabet].find((ch) => RESERVED_KEYS.includes(ch));
    if (clash) {
      return { ok: false, reason: `'${clash}' 는 이동/명령 키로 예약되어 있습니다` };
    }
    return { ok: true };
  }

  function loadConfig(raw) {
    const config = {
      leader: { ...DEFAULT_CONFIG.leader },
      alphabet: DEFAULT_CONFIG.alphabet,
      scrollAmount: DEFAULT_CONFIG.scrollAmount,
    };
    if (!raw) return config;

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return config;
    }
    if (!parsed || typeof parsed !== 'object') return config;

    if (validateAlphabet(parsed.alphabet).ok) config.alphabet = parsed.alphabet;
    if (Number.isFinite(parsed.scrollAmount) && parsed.scrollAmount > 0) {
      config.scrollAmount = parsed.scrollAmount;
    }
    if (parsed.leader && typeof parsed.leader.key === 'string' && parsed.leader.key) {
      config.leader = {
        key: parsed.leader.key,
        ctrl: !!parsed.leader.ctrl,
        meta: !!parsed.leader.meta,
        alt: !!parsed.leader.alt,
        shift: !!parsed.leader.shift,
      };
    }
    return config;
  }

  // ─── Node test export ────────────────────────────────────────────

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      generateLabels, latinChar, resolveHintChar, passesGeometry, passesStyle, orderByScreenPosition,
      validateAlphabet, loadConfig, DEFAULT_CONFIG,
    };
    return; // no DOM in Node; stop before init
  }

  // ─── runtime ─────────────────────────────────────────────────────

  const STORAGE_KEY = 'claude-vimium:config';
  let config = loadConfig(localStorage.getItem(STORAGE_KEY));

  function saveConfig(next) {
    config = next;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }

  function describeLeader(l) {
    const parts = [];
    if (l.ctrl) parts.push('Ctrl');
    if (l.alt) parts.push('Alt');
    if (l.shift) parts.push('Shift');
    if (l.meta) parts.push('Cmd');
    parts.push(l.key === ' ' ? 'Space' : l.key);
    return parts.join('+');
  }

  function openPanel(title, buildBody) {
    hideHints();
    const backdrop = document.createElement('div');
    backdrop.style.cssText = [
      'position:fixed', 'inset:0', 'z-index:2147483647',
      'background:rgba(0,0,0,.45)', 'display:flex',
      'align-items:center', 'justify-content:center',
      'font:13px/1.5 system-ui,sans-serif',
    ].join(';');

    const panel = document.createElement('div');
    panel.style.cssText = [
      'min-width:340px', 'max-width:90vw', 'max-height:80vh', 'overflow:auto',
      'padding:20px', 'border-radius:10px', 'background:#fff', 'color:#111',
      'box-shadow:0 8px 32px rgba(0,0,0,.3)',
    ].join(';');

    const heading = document.createElement('h2');
    heading.textContent = title;
    heading.style.cssText = 'margin:0 0 12px;font-size:15px';
    panel.appendChild(heading);

    const cleanups = [];
    const close = () => {
      // Body-registered teardown runs first: it may hold listeners that
      // outlive the panel's own DOM (the leader-key capture is one).
      while (cleanups.length) cleanups.pop()();
      backdrop.remove();
      document.removeEventListener('keydown', onPanelKey, true);
    };
    function onPanelKey(e) {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        close();
      }
    }
    document.addEventListener('keydown', onPanelKey, true);
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });

    buildBody(panel, close, (fn) => cleanups.push(fn));
    backdrop.appendChild(panel);
    document.body.appendChild(backdrop);
    return close;
  }

  function openSettings() {
    openPanel('claude-vimium 설정', (panel, close, onCleanup) => {
      const draft = { ...config, leader: { ...config.leader } };

      const leaderRow = document.createElement('div');
      leaderRow.style.cssText = 'margin-bottom:12px';
      const leaderBtn = document.createElement('button');
      leaderBtn.textContent = describeLeader(draft.leader);
      leaderBtn.style.cssText = 'padding:4px 10px;font:inherit';
      leaderBtn.addEventListener('click', () => {
        leaderBtn.textContent = '키를 누르세요…';

        const stop = () => document.removeEventListener('keydown', capture, true);

        function capture(e) {
          if (['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) return;
          e.preventDefault();
          e.stopPropagation();
          draft.leader = {
            key: e.key, ctrl: e.ctrlKey, meta: e.metaKey,
            alt: e.altKey, shift: e.shiftKey,
          };
          leaderBtn.textContent = describeLeader(draft.leader);
          stop();
        }

        document.addEventListener('keydown', capture, true);
        onCleanup(stop);
      });
      leaderRow.append('리더 키: ', leaderBtn);

      const alphaRow = document.createElement('div');
      alphaRow.style.cssText = 'margin-bottom:12px';
      const alphaInput = document.createElement('input');
      alphaInput.value = draft.alphabet;
      alphaInput.style.cssText = 'padding:4px 8px;font:inherit;width:220px';
      alphaRow.append('힌트 문자셋: ', alphaInput);

      const scrollRow = document.createElement('div');
      scrollRow.style.cssText = 'margin-bottom:12px';
      const scrollInput = document.createElement('input');
      scrollInput.type = 'number';
      scrollInput.value = String(draft.scrollAmount);
      scrollInput.style.cssText = 'padding:4px 8px;font:inherit;width:80px';
      scrollRow.append('스크롤 양(px): ', scrollInput);

      const error = document.createElement('div');
      error.style.cssText = 'color:#c00;min-height:20px;margin-bottom:8px';

      const save = document.createElement('button');
      save.textContent = '저장';
      save.style.cssText = 'padding:5px 14px;font:inherit';
      save.addEventListener('click', () => {
        const check = validateAlphabet(alphaInput.value);
        if (!check.ok) {
          error.textContent = check.reason;
          return;
        }
        const amount = Number(scrollInput.value);
        if (!Number.isFinite(amount) || amount <= 0) {
          error.textContent = '스크롤 양은 0보다 큰 숫자여야 합니다';
          return;
        }
        saveConfig({ leader: draft.leader, alphabet: alphaInput.value, scrollAmount: amount });
        close();
        toast('설정을 저장했습니다');
      });

      panel.append(leaderRow, alphaRow, scrollRow, error, save);
    });
  }

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
  let scrollerCache = null;

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

  // Find the scrollable container by measurement, never by class name —
  // the bundle's class names are hashed and change every app update.
  function findScroller() {
    if (scrollerCache && scrollerCache.isConnected) return scrollerCache;

    let best = document.scrollingElement || document.body;
    let bestArea = 0;
    for (const el of document.querySelectorAll('div,main,section')) {
      if (el.scrollHeight - el.clientHeight < 40) continue;
      if (!/auto|scroll/.test(getComputedStyle(el).overflowY)) continue;
      const r = el.getBoundingClientRect();
      const area = r.width * r.height;
      if (area > bestArea) {
        bestArea = area;
        best = el;
      }
    }
    scrollerCache = best;
    return best;
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
    scrollerCache = null;
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

  function scrollBy(dx, dy) {
    findScroller().scrollBy({ top: dy, left: dx, behavior: 'instant' });
    queueReposition();
  }

  const SCROLL_KEYS = {
    j: (c) => scrollBy(0, c.scrollAmount),
    k: (c) => scrollBy(0, -c.scrollAmount),
    h: (c) => scrollBy(-c.scrollAmount, 0),
    l: (c) => scrollBy(c.scrollAmount, 0),
  };

  const ARROW_KEYS = {
    ArrowDown: (c) => scrollBy(0, c.scrollAmount),
    ArrowUp: (c) => scrollBy(0, -c.scrollAmount),
    ArrowLeft: (c) => scrollBy(-c.scrollAmount, 0),
    ArrowRight: (c) => scrollBy(c.scrollAmount, 0),
  };

  // Returns true when the key was a scroll command and has been handled.
  function handleScrollKey(e) {
    if (e.ctrlKey && !e.metaKey && !e.altKey) {
      const ch = latinChar(e);
      if (ch === 'd' || ch === 'u') {
        const page = findScroller().clientHeight / 2;
        scrollBy(0, ch === 'd' ? page : -page);
        return true;
      }
      return false;
    }

    if (e.key === 'Home' || e.key === 'End') {
      const scroller = findScroller();
      scroller.scrollTo({ top: e.key === 'Home' ? 0 : scroller.scrollHeight, behavior: 'instant' });
      queueReposition();
      return true;
    }

    const arrow = ARROW_KEYS[e.key];
    if (arrow) {
      arrow(config);
      return true;
    }

    if (e.ctrlKey || e.metaKey || e.altKey) return false;

    // Letter keys go through latinChar so hjkl work on a Korean layout too,
    // where e.key would be a jamo.
    const handler = SCROLL_KEYS[latinChar(e)];
    if (!handler) return false;
    handler(config);
    return true;
  }

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

    if (e.key === ',') {
      openSettings();
      return;
    }

    if (handleScrollKey(e)) return;

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
