# claude-vimium Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Desktop에서 리더 키 한 번으로 화면의 클릭 가능한 요소에 힌트 라벨을 띄우고 키보드만으로 실행하는 확장을 만들고, 설치·자동 복구까지 완성한다.

**Architecture:** 의존성 0의 단일 파일 `src/claude-vimium.js`가 `ion-dist/index.html`에 주입되어 앱 렌더러 안에서 동작한다. 순수 함수(라벨 생성, 기하/스타일 필터)는 파일 하단의 조건부 `module.exports`로 Node에서 테스트하고, DOM 통합은 DevTools 콘솔에 붙여넣어 수동 검증한다. `install.sh`가 주입·복구를 담당하고 LaunchAgent가 앱 업데이트 후 재주입한다.

**Tech Stack:** 순수 JavaScript (ES2020), Node의 `assert` (테스트), POSIX sh (설치), macOS `launchd`.

## Global Constraints

- 외부 의존성 0, 빌드 스텝 없음. `npm install`이 필요한 코드를 추가하지 않는다
- 확장 본체는 `src/claude-vimium.js` 단일 파일
- **클래스명 기반 셀렉터 금지.** 앱 번들의 클래스명은 해시되어 있다. 역할 기반 셀렉터만 사용한다
- 리더 키 기본값: `Ctrl+;`
- 힌트 문자셋 기본값: `asdfgqwertzxcv` (왼손 영역, 14자)
- 예약 키 (힌트 문자셋에 들어갈 수 없음): `h`, `j`, `k`, `l`, `,`, `?`
- 스크롤 양 기본값: 60px
- 커밋 메시지는 영어
- 앱 경로: `/Applications/Claude.app/Contents/Resources/ion-dist/`

## 개발 루프

앱을 재시작하지 않고 반복한다:

1. `src/claude-vimium.js`를 편집
2. Claude Desktop에서 `Cmd+Alt+I`로 DevTools를 열고 파일 내용을 콘솔에 붙여넣어 실행
3. 동작 확인
4. 다시 편집

이것이 성립하려면 스크립트가 **재실행 안전**해야 한다 (Task 2에서 구축). 실제 설치(`install.sh`)는 기능이 완성된 뒤 Task 9에서 한 번 한다.

## File Structure

| 파일 | 책임 |
|---|---|
| `src/claude-vimium.js` | 확장 본체 전부. 순수 함수 + DOM 계층 + 초기화. 하단 조건부 export로 테스트 노출 |
| `test/labels.test.js` | 라벨 생성 순수 함수 테스트 |
| `test/filters.test.js` | 기하/스타일 필터 순수 함수 테스트 |
| `install.sh` | 설치 / 상태 / 제거 / LaunchAgent 등록 |
| `README.md` | 설치법, 키 바인딩, LaunchAgent가 하는 일, 제거법 |
| `.gitignore` | `.DS_Store` |

단일 파일 원칙은 **배포 산출물** 기준이다. 파일 안에서는 순수 함수 → DOM 계층 → 초기화 순으로 구역을 나눈다.

---

### Task 1: CSP 검증 스파이크

`<script src>`가 CSP에 막히는지 확인한다. **이 결과가 Task 9의 설치 방식을 결정하므로 가장 먼저 한다.**

**Files:**
- Create: `docs/superpowers/notes/csp-verification.md`

**Interfaces:**
- Consumes: 없음
- Produces: `INJECTION_MODE` 결정값 — `"src"` (외부 파일 참조) 또는 `"inline"` (내용 직접 삽입). Task 9가 이 값을 사용한다

- [ ] **Step 1: 검증용 스크립트를 배치**

```bash
printf 'console.log("[claude-vimium] CSP OK");\n' > "/Applications/Claude.app/Contents/Resources/ion-dist/claude-vimium-probe.js"
```

- [ ] **Step 2: index.html 백업 후 script 태그 주입**

```bash
DIST="/Applications/Claude.app/Contents/Resources/ion-dist"
cp "$DIST/index.html" "$DIST/index.html.probe.bak"
sed -i '' 's#</body>#<script src="/claude-vimium-probe.js"></script></body>#' "$DIST/index.html"
grep -c 'claude-vimium-probe' "$DIST/index.html"
```

Expected: `1`

- [ ] **Step 3: 앱을 완전히 종료했다가 다시 실행**

이 단계는 사람이 직접 한다. Claude Desktop을 종료(`Cmd+Q`)하고 다시 연다. 현재 세션이 앱 안에서 돌고 있다면 세션이 끊기므로, 재시작 후 이 계획 문서를 다시 열어 이어간다.

- [ ] **Step 4: 콘솔 확인**

`Cmd+Alt+I`로 DevTools를 열고 Console 탭을 본다.

- `[claude-vimium] CSP OK`가 보이면 → `INJECTION_MODE = "src"`
- 아무것도 없고 CSP 위반 에러(`Refused to load the script ...`)가 보이면 → `INJECTION_MODE = "inline"`
- 둘 다 없으면 주입 자체가 실패한 것이다. Step 2의 `grep` 결과를 다시 확인한다

- [ ] **Step 5: 원복**

```bash
DIST="/Applications/Claude.app/Contents/Resources/ion-dist"
mv "$DIST/index.html.probe.bak" "$DIST/index.html"
rm -f "$DIST/claude-vimium-probe.js"
```

- [ ] **Step 6: 결과를 기록하고 커밋**

`docs/superpowers/notes/csp-verification.md`에 다음을 적는다: 확인 날짜, 앱 버전(`defaults read /Applications/Claude.app/Contents/Info.plist CFBundleShortVersionString`), 콘솔에서 본 것 그대로, 결정된 `INJECTION_MODE`.

```bash
git add docs/superpowers/notes/csp-verification.md
git commit -m "docs: record CSP verification result for script injection"
```

---

### Task 2: 프로젝트 스캐폴드와 재실행 안전 초기화

개발 루프의 토대. 콘솔에 반복해서 붙여넣어도 중복 인스턴스가 생기지 않게 한다.

**Files:**
- Create: `src/claude-vimium.js`
- Create: `.gitignore`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `window.__claudeVimium` — 현재 인스턴스 핸들. `{ teardown(): void }` 형태
  - 파일 하단 조건부 export: `module.exports = { generateLabels, passesGeometry, passesStyle }` (Node에서만)

- [ ] **Step 1: `.gitignore` 작성**

```
.DS_Store
```

- [ ] **Step 2: `src/claude-vimium.js` 뼈대 작성**

```javascript
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
```

- [ ] **Step 3: 재실행 안전성을 콘솔에서 확인**

Claude Desktop에서 `Cmd+Alt+I` → Console에 파일 내용 전체를 붙여넣고 Enter. **두 번** 반복한다.

Expected: `[claude-vimium] ready`가 두 번 찍히고, 에러가 없으며, `window.__claudeVimium`이 정의되어 있다.

콘솔에서 확인:

```javascript
typeof window.__claudeVimium.teardown === 'function'
```

Expected: `true`

- [ ] **Step 4: 커밋**

```bash
git add .gitignore src/claude-vimium.js
git commit -m "feat: add re-runnable extension skeleton with teardown"
```

---

### Task 3: 라벨 생성

접두사 충돌이 없는 힌트 라벨을 만든다. 순수 함수이므로 Node에서 테스트한다.

**Files:**
- Create: `test/labels.test.js`
- Modify: `src/claude-vimium.js` (pure helpers 구역, Node export)

**Interfaces:**
- Consumes: Task 2의 파일 구조와 조건부 export
- Produces: `generateLabels(count: number, alphabet: string): string[]`
  - 반환 배열 길이는 `Math.min(count, alphabet.length ** 2)`
  - 어떤 라벨도 다른 라벨의 접두사가 아니다
  - `alphabet`이 빈 문자열이면 `Error`를 던진다

- [ ] **Step 1: 실패하는 테스트 작성**

`test/labels.test.js`:

```javascript
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
```

- [ ] **Step 2: 실패 확인**

Run: `node test/labels.test.js`
Expected: FAIL — `TypeError: generateLabels is not a function`

- [ ] **Step 3: 구현**

`src/claude-vimium.js`의 pure helpers 구역에 추가:

```javascript
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
```

그리고 Node export를 갱신:

```javascript
    module.exports = { generateLabels };
```

- [ ] **Step 4: 통과 확인**

Run: `node test/labels.test.js`
Expected: PASS — `labels.test.js OK`

- [ ] **Step 5: 커밋**

```bash
git add test/labels.test.js src/claude-vimium.js
git commit -m "feat: add prefix-free hint label generation"
```

---

### Task 4: 힌트 대상 필터

어떤 요소에 힌트를 붙일지 판정한다. 기하·스타일 판정은 순수 함수로 분리해 Node에서 테스트하고, DOM 수집은 그 위에 얹는다.

**Files:**
- Create: `test/filters.test.js`
- Modify: `src/claude-vimium.js` (pure helpers 구역, runtime 구역, Node export)

**Interfaces:**
- Consumes: Task 3의 파일 구조
- Produces:
  - `passesGeometry(rect: {top,left,bottom,right,width,height}, viewport: {width,height}): boolean`
  - `passesStyle(style: {display,visibility,opacity}): boolean`
  - `collectTargets(): Element[]` — 화면 순서(위→아래, 좌→우)로 정렬된 힌트 대상. Task 5·6이 사용한다
  - `HINT_SELECTOR: string`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/filters.test.js`:

```javascript
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
```

- [ ] **Step 2: 실패 확인**

Run: `node test/filters.test.js`
Expected: FAIL — `TypeError: passesGeometry is not a function`

- [ ] **Step 3: 순수 함수 구현**

pure helpers 구역에 추가:

```javascript
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
```

Node export 갱신:

```javascript
    module.exports = { generateLabels, passesGeometry, passesStyle };
```

- [ ] **Step 4: 통과 확인**

Run: `node test/filters.test.js`
Expected: PASS — `filters.test.js OK`

- [ ] **Step 5: DOM 수집 계층 구현**

runtime 구역, `init()` 위에 추가:

```javascript
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
```

- [ ] **Step 6: 콘솔에서 수집 결과 확인**

파일 전체를 콘솔에 붙여넣은 뒤:

```javascript
collectTargets === undefined // 스코프 밖이므로 직접 호출 불가 — 아래처럼 확인
```

`init()` 안 `window.__claudeVimium` 객체에 디버그용으로 노출한다:

```javascript
    window.__claudeVimium = { teardown, on, collectTargets };
```

콘솔에서:

```javascript
window.__claudeVimium.collectTargets().length
```

Expected: 0보다 큰 수. 입력창·모델 메뉴·사이드바 버튼이 포함되어야 한다. 다음으로 눈으로 확인:

```javascript
window.__claudeVimium.collectTargets().forEach(el => el.style.outline = '2px solid lime')
```

Expected: 화면의 클릭 가능한 요소들에 테두리가 생기고, 큰 컨테이너가 아니라 실제 버튼에 붙는다. 확인 후 `Cmd+R`로 리로드해 지운다.

- [ ] **Step 7: 커밋**

```bash
git add test/filters.test.js src/claude-vimium.js
git commit -m "feat: add hint target discovery with geometry and style filters"
```

---

### Task 5: 오버레이 렌더링과 생명주기

라벨을 화면에 그리고, 스크롤·리사이즈·DOM 변경에도 위치를 따라가게 한다.

**Files:**
- Modify: `src/claude-vimium.js` (runtime 구역)

**Interfaces:**
- Consumes: `collectTargets()`, `generateLabels()`
- Produces:
  - `showHints(): void` — 대상 수집, 라벨 배정, 오버레이 렌더
  - `hideHints(): void` — 오버레이 제거, 리스너 해제
  - `hintState: { active: boolean, entries: Array<{el: Element, label: string, node: HTMLElement}>, typed: string }`
  - `filterHints(typed: string): void` — 입력에 맞지 않는 라벨 숨김

- [ ] **Step 1: 오버레이 구현**

runtime 구역에 추가:

```javascript
  const OVERLAY_ID = 'claude-vimium-overlay';
  const hintState = { active: false, entries: [], typed: '' };
  let overlayEl = null;
  let repositionQueued = false;
  let observer = null;

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
    node.textContent = label;
    node.style.cssText = [
      'position:fixed',
      'padding:1px 3px',
      'border-radius:3px',
      'background:#ffd400',
      'color:#000',
      'box-shadow:0 1px 3px rgba(0,0,0,.4)',
      'white-space:nowrap',
    ].join(';');
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
  }

  function filterHints(typed) {
    for (const entry of hintState.entries) {
      const match = entry.label.startsWith(typed);
      entry.node.style.display = match ? '' : 'none';
      entry.node.style.opacity = match && typed ? '1' : '';
    }
    placeLabels();
  }
```

- [ ] **Step 2: 토스트와 설정 기본값 추가**

`showHints`가 참조하는 `toast`와 `config`를 runtime 구역 상단에 추가한다. `config`는 Task 8에서 localStorage 연동으로 대체된다.

```javascript
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
```

- [ ] **Step 3: 디버그 노출 갱신**

```javascript
    window.__claudeVimium = { teardown, on, collectTargets, showHints, hideHints, hintState };
```

- [ ] **Step 4: 콘솔에서 수동 검증**

파일 전체를 콘솔에 붙여넣고:

```javascript
window.__claudeVimium.showHints()
```

Expected: 클릭 가능한 요소마다 노란 라벨이 붙는다. 겹쳐서 읽을 수 없는 라벨이 없다.

이어서 대화창을 스크롤한다.

Expected: 라벨이 요소를 따라 움직인다. 원래 자리에 남지 않는다.

창 크기를 바꾼다.

Expected: 라벨이 새 위치로 따라간다.

```javascript
window.__claudeVimium.hideHints()
```

Expected: 라벨이 모두 사라진다.

- [ ] **Step 5: 커밋**

```bash
git add src/claude-vimium.js
git commit -m "feat: render hint overlay with scroll and mutation tracking"
```

---

### Task 6: 키 처리, 모드 전환, 요소 실행

리더 키로 힌트를 띄우고, 라벨을 입력해 요소를 실행하고, 모드를 빠져나온다. 이 태스크가 끝나면 확장의 핵심 기능이 동작한다.

**Files:**
- Modify: `src/claude-vimium.js` (runtime 구역)

**Interfaces:**
- Consumes: `showHints()`, `hideHints()`, `filterHints()`, `hintState`, `config`
- Produces:
  - `matchesLeader(event: KeyboardEvent): boolean`
  - `activate(el: Element): void` — 입력 요소는 `focus()`, 나머지는 `click()`
  - `onKeyDown(event: KeyboardEvent): void` — 캡처 단계 핸들러

- [ ] **Step 1: 키 처리 구현**

runtime 구역에 추가:

```javascript
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
    // Never touch keys while an IME is composing — intercepting them
    // corrupts Korean and Japanese input mid-syllable.
    if (e.isComposing || e.keyCode === 229) return;

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
      hintState.typed = hintState.typed.slice(0, -1);
      filterHints(hintState.typed);
      return;
    }

    if (e.key.length !== 1) return;

    const next = hintState.typed + e.key;
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
```

- [ ] **Step 2: `init()`에서 핸들러 등록**

`init()` 안, `window.__claudeVimium` 할당 전에 추가:

```javascript
    on(window, 'keydown', onKeyDown, true);
```

`teardown()`이 이미 모든 리스너를 해제하므로 추가 정리는 필요 없다. 단, 힌트가 떠 있는 채로 teardown되면 오버레이가 남으므로 `teardown` 본문 첫 줄에 추가:

```javascript
      hideHints();
```

- [ ] **Step 3: 콘솔에서 수동 검증**

파일 전체를 콘솔에 붙여넣은 뒤 **콘솔이 아니라 앱 창을 클릭해 포커스를 옮기고** 다음을 확인한다.

| 확인 | 기대 |
|---|---|
| `Ctrl+;` | 힌트가 즉시 뜬다 |
| 라벨 첫 글자 입력 | 매칭 안 되는 라벨이 사라진다 |
| `Backspace` | 사라졌던 라벨이 돌아온다 |
| 라벨 완성 | 해당 버튼이 눌리고 힌트가 사라진다 |
| 입력창 라벨 완성 | 커서가 입력창에 들어간다 (클릭이 아니라 포커스) |
| 라벨에 없는 글자 | 오버레이가 짧게 흔들리고 모드는 유지된다 |
| `Esc` | 힌트가 사라진다 |
| 입력창에 한글 타이핑 | 정상 입력된다. 힌트가 뜨거나 글자가 깨지지 않는다 |
| 한글 조합 중 `Ctrl+;` | 조합이 깨지지 않는다 |

- [ ] **Step 4: 커밋**

```bash
git add src/claude-vimium.js
git commit -m "feat: add leader key, label matching, and element activation"
```

---

### Task 7: 스크롤 커맨드

힌트 모드 안에서 스크롤한다. 힌트 문자셋과 겹치지 않는 오른손 키만 쓴다.

**Files:**
- Modify: `src/claude-vimium.js` (runtime 구역)

**Interfaces:**
- Consumes: `config.scrollAmount`, `onKeyDown`
- Produces: `scrollBy(dx: number, dy: number): void`, `findScroller(): Element` — 스크롤 대상 컨테이너

- [ ] **Step 1: 스크롤 대상 탐색과 스크롤 구현**

runtime 구역에 추가:

```javascript
  // The conversation lives in a scrollable div, not on document.scrollingElement.
  // Pick the largest visible element that actually overflows — again by
  // measurement, never by class name.
  function findScroller() {
    let best = document.scrollingElement || document.body;
    let bestArea = 0;
    for (const el of document.querySelectorAll('div,main,section')) {
      if (el.scrollHeight - el.clientHeight < 40) continue;
      const style = getComputedStyle(el);
      if (!/auto|scroll/.test(style.overflowY)) continue;
      const r = el.getBoundingClientRect();
      const area = r.width * r.height;
      if (area > bestArea) {
        bestArea = area;
        best = el;
      }
    }
    return best;
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
    ArrowDown: (c) => scrollBy(0, c.scrollAmount),
    ArrowUp: (c) => scrollBy(0, -c.scrollAmount),
    ArrowLeft: (c) => scrollBy(-c.scrollAmount, 0),
    ArrowRight: (c) => scrollBy(c.scrollAmount, 0),
  };

  function handleScrollKey(e) {
    if (e.ctrlKey && (e.key === 'd' || e.key === 'u')) {
      const page = findScroller().clientHeight / 2;
      scrollBy(0, e.key === 'd' ? page : -page);
      return true;
    }
    if (e.key === 'Home' || e.key === 'End') {
      const scroller = findScroller();
      scroller.scrollTo({ top: e.key === 'Home' ? 0 : scroller.scrollHeight, behavior: 'instant' });
      queueReposition();
      return true;
    }
    if (e.ctrlKey || e.metaKey || e.altKey) return false;
    const handler = SCROLL_KEYS[e.key];
    if (!handler) return false;
    handler(config);
    return true;
  }
```

- [ ] **Step 2: `onKeyDown`에 연결**

`onKeyDown` 안, `Backspace` 처리 **다음**이자 `e.key.length !== 1` 검사 **앞**에 추가:

```javascript
    if (handleScrollKey(e)) return;
```

순서가 중요하다. 스크롤 키가 라벨 매칭보다 먼저 처리되어야 하며, 예약 키이므로 라벨에 나타나지 않는다.

- [ ] **Step 3: 콘솔에서 수동 검증**

파일을 붙여넣고 앱 창에 포커스를 준 뒤 `Ctrl+;`로 힌트를 띄운 상태에서:

| 키 | 기대 |
|---|---|
| `j` / `k` | 대화가 아래/위로 스크롤되고 라벨이 따라 움직인다 |
| `↓` / `↑` | 같음 |
| `Ctrl+d` / `Ctrl+u` | 반 페이지씩 이동 |
| `Home` / `End` | 대화 맨 위 / 맨 아래 |
| `h` / `l` | 코드 블록처럼 가로 스크롤이 있는 곳에서 좌우 이동 |

스크롤 후에도 라벨을 완성하면 올바른 요소가 눌리는지 확인한다.

- [ ] **Step 4: 커밋**

```bash
git add src/claude-vimium.js
git commit -m "feat: add scroll commands inside hint mode"
```

---

### Task 8: 설정 저장·검증과 설정 화면

`localStorage`에 설정을 저장하고, 리더 키·문자셋·스크롤 양을 바꿀 수 있게 한다.

**Files:**
- Create: `test/config.test.js`
- Modify: `src/claude-vimium.js` (pure helpers, runtime, Node export)

**Interfaces:**
- Consumes: `config`, `RESERVED_KEYS`, `hintState`
- Produces:
  - `validateAlphabet(alphabet: string): {ok: true} | {ok: false, reason: string}`
  - `loadConfig(raw: string | null): Config` — 손상된 값은 기본값으로 폴백
  - `openSettings(): void`
  - `Config = { leader: {key, ctrl, meta, alt, shift}, alphabet: string, scrollAmount: number }`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/config.test.js`:

```javascript
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
```

- [ ] **Step 2: 실패 확인**

Run: `node test/config.test.js`
Expected: FAIL — `TypeError: validateAlphabet is not a function`

- [ ] **Step 3: 구현**

pure helpers 구역에 추가한다. **동시에 두 곳을 지운다** — Task 5에서 runtime 구역에 넣었던 `const config = {...}` 리터럴, 그리고 Task 6에서 runtime 구역에 넣었던 `const RESERVED_KEYS = [...]`. 둘 다 아래 선언으로 대체되며, 남겨두면 중복 선언으로 `SyntaxError`가 난다.

```javascript
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
```

Node export 갱신:

```javascript
    module.exports = {
      generateLabels, passesGeometry, passesStyle,
      validateAlphabet, loadConfig, DEFAULT_CONFIG,
    };
```

- [ ] **Step 4: 통과 확인**

Run: `node test/config.test.js`
Expected: PASS — `config.test.js OK`

- [ ] **Step 5: 런타임 연동과 설정 화면 구현**

runtime 구역에 추가:

```javascript
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

    const close = () => {
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

    buildBody(panel, close);
    backdrop.appendChild(panel);
    document.body.appendChild(backdrop);
    return close;
  }

  function openSettings() {
    openPanel('claude-vimium 설정', (panel, close) => {
      const draft = { ...config, leader: { ...config.leader } };

      const leaderRow = document.createElement('div');
      leaderRow.style.cssText = 'margin-bottom:12px';
      const leaderBtn = document.createElement('button');
      leaderBtn.textContent = describeLeader(draft.leader);
      leaderBtn.style.cssText = 'padding:4px 10px;font:inherit';
      leaderBtn.addEventListener('click', () => {
        leaderBtn.textContent = '키를 누르세요…';
        const capture = (e) => {
          if (['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) return;
          e.preventDefault();
          e.stopPropagation();
          draft.leader = {
            key: e.key, ctrl: e.ctrlKey, meta: e.metaKey,
            alt: e.altKey, shift: e.shiftKey,
          };
          leaderBtn.textContent = describeLeader(draft.leader);
          document.removeEventListener('keydown', capture, true);
        };
        document.addEventListener('keydown', capture, true);
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
```

- [ ] **Step 6: `onKeyDown`에 `,` 연결**

`onKeyDown` 안, `handleScrollKey` 호출 **앞**에 추가:

```javascript
    if (e.key === ',') {
      openSettings();
      return;
    }
```

- [ ] **Step 7: 수동 검증**

| 확인 | 기대 |
|---|---|
| `Ctrl+;` → `,` | 설정 패널이 열리고 힌트는 사라진다 |
| 리더 키 버튼 클릭 후 `Ctrl+'` | 버튼 라벨이 `Ctrl+'`로 바뀐다 |
| 문자셋에 `hjkl` 입력 후 저장 | 저장되지 않고 `'h' 는 이동/명령 키로 예약되어 있습니다` 표시 |
| 문자셋에 `aab` 입력 후 저장 | `중복된 문자가 있습니다` 표시 |
| 유효한 값으로 저장 | 패널이 닫히고 토스트가 뜬다 |
| 바꾼 리더 키로 힌트 호출 | 새 키로 동작한다 |
| `Cmd+R` 리로드 후 파일 재실행 | 바꾼 설정이 유지된다 |
| 패널에서 `Esc` | 패널만 닫힌다 |

- [ ] **Step 8: 커밋**

```bash
git add test/config.test.js src/claude-vimium.js
git commit -m "feat: add persisted config with validation and settings panel"
```

---

### Task 9: 도움말 오버레이

`?`로 현재 적용 중인 바인딩을 보여준다.

**Files:**
- Modify: `src/claude-vimium.js` (runtime 구역)

**Interfaces:**
- Consumes: `openPanel()`, `config`, `describeLeader()`
- Produces: `openHelp(): void`

- [ ] **Step 1: 구현**

runtime 구역, `openSettings` 아래에 추가:

```javascript
  function openHelp() {
    openPanel('claude-vimium 키 바인딩', (panel) => {
      const rows = [
        [describeLeader(config.leader), '힌트 모드 진입 / 종료'],
        [config.alphabet.slice(0, 4) + '…', '힌트 라벨 입력 (현재 문자셋)'],
        ['h j k l', '좌 하 상 우 스크롤'],
        ['↑ ↓ ← →', '같음'],
        ['Ctrl+d / Ctrl+u', '반 페이지 아래 / 위'],
        ['Home / End', '맨 위 / 맨 아래'],
        ['Backspace', '입력한 라벨 한 글자 취소'],
        [',', '설정'],
        ['?', '이 도움말'],
        ['Esc', '모드 종료'],
      ];

      const table = document.createElement('table');
      table.style.cssText = 'border-collapse:collapse';
      for (const [keys, description] of rows) {
        const tr = document.createElement('tr');
        const kbd = document.createElement('td');
        kbd.textContent = keys;
        kbd.style.cssText =
          'padding:3px 14px 3px 0;font:600 12px ui-monospace,Menlo,monospace;white-space:nowrap';
        const desc = document.createElement('td');
        desc.textContent = description;
        desc.style.cssText = 'padding:3px 0';
        tr.append(kbd, desc);
        table.appendChild(tr);
      }
      panel.appendChild(table);
    });
  }
```

`config.alphabet`을 그대로 읽으므로 사용자가 문자셋이나 리더 키를 바꾸면 도움말도 바뀐 값을 보여준다.

- [ ] **Step 2: `onKeyDown`에 `?` 연결**

`,` 처리 바로 아래에 추가:

```javascript
    if (e.key === '?') {
      openHelp();
      return;
    }
```

- [ ] **Step 3: 수동 검증**

| 확인 | 기대 |
|---|---|
| `Ctrl+;` → `?` | 도움말이 열리고 리더 키가 `Ctrl+;`로 표시된다 |
| 설정에서 리더 키를 바꾼 뒤 다시 `?` | 바뀐 키가 표시된다 (기본값이 아님) |
| `Esc` | 도움말이 닫힌다 |

- [ ] **Step 4: 커밋**

```bash
git add src/claude-vimium.js
git commit -m "feat: add help overlay reflecting effective bindings"
```

---

### Task 10: install.sh

설치·상태 확인·제거. Task 1에서 결정한 `INJECTION_MODE`를 반영한다.

**Files:**
- Create: `install.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: Task 1의 `INJECTION_MODE`, `src/claude-vimium.js`
- Produces: `install.sh` — 서브커맨드 `install`(기본) / `status` / `uninstall`, 플래그 `--no-auto`

- [ ] **Step 1: `install.sh` 작성**

아래는 `INJECTION_MODE = "src"` 기준이다. Task 1이 `"inline"`으로 판정했다면 `inject()` 함수만 교체한다 (Step 2 참조).

```sh
#!/bin/sh
# claude-vimium installer — injects the extension into Claude Desktop's UI bundle.
set -eu

APP="/Applications/Claude.app"
DIST="$APP/Contents/Resources/ion-dist"
INDEX="$DIST/index.html"
BACKUP="$DIST/index.html.claude-vimium.bak"
PAYLOAD="$DIST/claude-vimium.js"
TAG='<script src="/claude-vimium.js"></script>'
MARKER='claude-vimium.js'

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$SRC_DIR/src/claude-vimium.js"

AGENT_LABEL="com.claude-vimium.reinstall"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

die() { echo "error: $*" >&2; exit 1; }

require_app() {
  [ -d "$APP" ] || die "Claude.app not found at $APP"
  [ -f "$INDEX" ] || die "UI bundle not found at $INDEX"
  [ -w "$INDEX" ] || die "$INDEX is not writable"
}

inject() {
  cp "$SOURCE" "$PAYLOAD"
  if grep -q "$MARKER" "$INDEX"; then
    echo "already injected — refreshed $PAYLOAD"
    return
  fi
  [ -f "$BACKUP" ] || cp "$INDEX" "$BACKUP"
  # The bundle has exactly one </body>, at the end of the file.
  sed -i '' "s#</body>#$TAG</body>#" "$INDEX"
  echo "injected into $INDEX"
}

install_agent() {
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$SRC_DIR/install.sh</string>
    <string>install</string>
    <string>--no-auto</string>
  </array>
  <key>WatchPaths</key>
  <array><string>$INDEX</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
  launchctl unload "$AGENT_PLIST" 2>/dev/null || true
  launchctl load "$AGENT_PLIST"
  echo "registered LaunchAgent $AGENT_LABEL"
  echo "  it watches $INDEX and re-injects after Claude updates"
  echo "  remove it with: $0 uninstall"
}

cmd_install() {
  require_app
  inject
  if [ "${NO_AUTO:-0}" = "1" ]; then
    echo "skipped LaunchAgent (--no-auto)"
  else
    install_agent
  fi
  echo "done — restart Claude Desktop to load the extension"
}

cmd_status() {
  [ -d "$APP" ] || die "Claude.app not found at $APP"
  version=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)
  echo "Claude.app version: $version"
  if grep -q "$MARKER" "$INDEX" 2>/dev/null; then
    echo "injection: present"
  else
    echo "injection: MISSING (run $0 install)"
  fi
  [ -f "$PAYLOAD" ] && echo "payload: $PAYLOAD" || echo "payload: missing"
  if launchctl list | grep -q "$AGENT_LABEL"; then
    echo "LaunchAgent: loaded"
  else
    echo "LaunchAgent: not loaded"
  fi
}

cmd_uninstall() {
  if [ -f "$AGENT_PLIST" ]; then
    launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    echo "removed LaunchAgent"
  fi
  if [ -f "$BACKUP" ]; then
    mv "$BACKUP" "$INDEX"
    echo "restored $INDEX from backup"
  elif grep -q "$MARKER" "$INDEX" 2>/dev/null; then
    sed -i '' "s#$TAG##" "$INDEX"
    echo "removed injection from $INDEX"
  fi
  rm -f "$PAYLOAD"
  echo "done — restart Claude Desktop"
}

NO_AUTO=0
COMMAND=install
for arg in "$@"; do
  case "$arg" in
    --no-auto) NO_AUTO=1 ;;
    install|status|uninstall) COMMAND=$arg ;;
    *) die "unknown argument: $arg" ;;
  esac
done

case "$COMMAND" in
  install) cmd_install ;;
  status) cmd_status ;;
  uninstall) cmd_uninstall ;;
esac
```

실행 권한 부여:

```bash
chmod +x install.sh
```

- [ ] **Step 2: `INJECTION_MODE = "inline"`인 경우에만 — `inject()` 교체**

Task 1이 CSP 차단으로 판정했을 때만 적용한다. `"src"`였다면 이 스텝을 건너뛴다.

```sh
inject() {
  if grep -q "$MARKER" "$INDEX"; then
    # An inline payload cannot be refreshed in place; restore first.
    [ -f "$BACKUP" ] && cp "$BACKUP" "$INDEX"
  fi
  [ -f "$BACKUP" ] || cp "$INDEX" "$BACKUP"
  tmp=$(mktemp)
  {
    sed 's#</body>##' "$INDEX"
    printf '<script data-claude-vimium>\n'
    cat "$SOURCE"
    printf '\n</script></body></html>\n'
  } > "$tmp"
  mv "$tmp" "$INDEX"
  echo "injected inline into $INDEX"
}
```

이 경우 `MARKER`를 `data-claude-vimium`으로, `PAYLOAD` 관련 줄을 제거한다. `</html>`이 중복되지 않도록 `sed` 대상에 `</html>`도 포함시킨다.

- [ ] **Step 3: 설치 검증**

```bash
./install.sh status
```

Expected: `injection: MISSING`

```bash
./install.sh
./install.sh status
```

Expected: `injection: present`, `LaunchAgent: loaded`

Claude Desktop을 재시작하고 `Ctrl+;`를 누른다.

Expected: 힌트가 뜬다. 콘솔에 붙여넣지 않아도 동작한다.

- [ ] **Step 4: 제거 검증**

```bash
./install.sh uninstall
./install.sh status
```

Expected: `injection: MISSING`, `LaunchAgent: not loaded`

```bash
grep -c 'claude-vimium' "/Applications/Claude.app/Contents/Resources/ion-dist/index.html" || true
```

Expected: `0` — `index.html`에 흔적이 남지 않는다. `|| true`는 grep이 아무것도 못 찾았을 때의 종료 코드 1을 삼킨다.

재설치해서 다시 동작하는지 확인한다:

```bash
./install.sh
```

- [ ] **Step 5: `README.md` 작성**

다음을 담는다:

- 무엇을 하는 확장인지 한 문단
- 키 바인딩 표 (Task 9의 도움말과 동일한 내용)
- 설치: `git clone` → `./install.sh` → Claude Desktop 재시작
- **LaunchAgent가 하는 일**: `index.html`을 감시하다가 앱 업데이트로 주입이 사라지면 다시 넣는다. `--no-auto`로 끌 수 있고 `./install.sh uninstall`로 제거된다
- 제거: `./install.sh uninstall`
- 알려진 제약: 앱 업데이트 시 주입이 사라진다는 점, `codesign --verify`가 실패한다는 점, macOS 전용
- 테스트 실행법: `node test/labels.test.js && node test/filters.test.js && node test/config.test.js`

- [ ] **Step 6: 커밋**

```bash
git add install.sh README.md
git commit -m "feat: add installer with LaunchAgent-based recovery"
```

---

### Task 11: 앱 업데이트 복구 검증

LaunchAgent가 실제로 재주입하는지 확인한다. 앱 업데이트를 기다릴 수 없으므로 교체를 흉내 낸다.

**Files:**
- Modify: `README.md` (검증 결과에 따라 제약 사항 갱신)

**Interfaces:**
- Consumes: Task 10의 `install.sh`, LaunchAgent
- Produces: 없음 (검증 태스크)

- [ ] **Step 1: 설치 상태 확인**

```bash
./install.sh status
```

Expected: `injection: present`, `LaunchAgent: loaded`

- [ ] **Step 2: 앱 업데이트를 흉내 내어 주입을 지운다**

```bash
DIST="/Applications/Claude.app/Contents/Resources/ion-dist"
cp "$DIST/index.html.claude-vimium.bak" "$DIST/index.html"
grep -c 'claude-vimium' "$DIST/index.html" || true
```

Expected: `0`

- [ ] **Step 3: LaunchAgent가 복구할 시간을 준다**

```bash
sleep 5
grep -c 'claude-vimium' "/Applications/Claude.app/Contents/Resources/ion-dist/index.html" || true
```

Expected: `1` — LaunchAgent가 `WatchPaths` 트리거로 깨어나 재주입했다.

`0`이 나오면 진단한다:

```bash
launchctl list | grep claude-vimium
log show --predicate 'process == "launchd"' --last 2m | grep claude-vimium
```

- [ ] **Step 4: 무한 루프가 없음을 확인**

```bash
sleep 10
grep -c 'claude-vimium.js' "/Applications/Claude.app/Contents/Resources/ion-dist/index.html"
```

Expected: `1` — 재주입이 반복되어 script 태그가 여러 개 쌓이지 않는다.

- [ ] **Step 5: 결과를 README에 반영하고 커밋**

복구가 동작하면 README의 LaunchAgent 설명에 "검증됨"을 적는다. 동작하지 않으면 알려진 제약에 그 사실과 수동 복구 명령(`./install.sh`)을 적는다.

```bash
git add README.md
git commit -m "docs: record LaunchAgent recovery verification"
```

---

## Self-Review

**Spec coverage**

| 스펙 항목 | 태스크 |
|---|---|
| §5.1 모드와 키 (리더, 힌트, 스크롤, `,`, `?`, `Esc`, `Backspace`) | 6, 7, 8, 9 |
| §5.2 키 이벤트 처리 (캡처, IME 가드, `key` 사용) | 6 |
| §5.3 힌트 대상 탐색 (역할 셀렉터, 필터, 중첩 제거) | 4 |
| §5.4 라벨 생성 (혼합 길이, 접두사 없음, 화면 순서, 입력 처리) | 3, 5, 6 |
| §5.5 오버레이 생명주기 (재계산, 겹침, 메뉴 재무장) | 5 |
| §5.6 요소 실행 (click / focus 분기) | 6 |
| §5.7 설정·도움말 (저장, 검증, 실제 바인딩 표시) | 8, 9 |
| §6 설치 (백업, 중복 방지, status, uninstall) | 10 |
| §6.1 앱 업데이트 대응 (WatchPaths, RunAtLoad, 루프 없음) | 10, 11 |
| §7 에러 처리 | 5(대상 0개), 6(불일치·요소 소실), 8(설정 손상·문자셋 충돌), 10(앱 없음·백업 보존) |
| §8 검증 (자체 검사 3종, 수동 체크리스트, status) | 3, 4, 8, 10 |
| §9 CSP 리스크 | 1 |

빠진 항목 없음.

**Placeholder scan**

"TBD", "적절한 에러 처리", "위 내용에 대한 테스트 작성" 같은 표현 없음. 모든 코드 스텝에 실제 코드가 있다. Task 10 Step 2는 조건부지만 교체할 코드를 전부 제시했다.

**Type consistency**

- `generateLabels(count, alphabet)` — Task 3에서 정의, Task 5에서 `generateLabels(targets.length, config.alphabet)`로 호출. 일치
- `passesGeometry(rect, viewport)` / `passesStyle(style)` — Task 4에서 정의·사용. 일치
- `config.alphabet` / `config.scrollAmount` / `config.leader` — Task 5에서 상수로 도입, Task 8에서 `loadConfig`로 대체하며 같은 형태 유지. Task 7의 `SCROLL_KEYS`가 `c.scrollAmount`로 받고, Task 9가 `config.alphabet`을 읽는다. 일치
- `hintState.entries[].{el,label,node}` — Task 5에서 정의, Task 6에서 동일 필드 사용. 일치
- `queueReposition()` — Task 5에서 정의, Task 7의 `scrollBy`가 호출. 일치
- `openPanel(title, buildBody)` — Task 8에서 정의, Task 9가 재사용. 일치
- `toast(message)` — Task 5에서 정의, Task 8이 사용. 일치
- `RESERVED_KEYS` — Task 6에서 먼저 선언되고 Task 8에서 pure helpers 구역으로 이동한다. **Task 8 Step 3에서 Task 6의 중복 선언을 제거할 것.**
- `MARKER` / `PAYLOAD` — Task 10 Step 1에서 정의, Step 2의 inline 분기에서 변경이 필요함을 명시했다
