# Claude Mods와 로컬 번들 조사 (2026-09-21)

Claude Mods 발표를 계기로 두 가지를 확인했다.

1. Mods로 이 확장을 데스크톱과 CLI 양쪽에서 쓸 수 있는가
2. 이제 설치 프로그램을 만들 수 있는가

둘 다 답은 "아니오"다. 결론은 안 바뀌었고, 바뀐 것은 **README가 대던 이유**다. 근거를 남겨 다음 사람이 같은 조사를 반복하지 않게 한다.

대상: Claude Desktop 2.2553.1, Claude Code CLI 2.1.278 (npm 최신), macOS 26.5.

---

## 1. Claude Mods

### 무엇인가

Claude Code 플러그인이되 동작이 TypeScript 모듈에 있는 것. `hooks/hooks.json` 이 `{"modules": ["./register.ts"]}` 로 모듈을 지목하고, 모듈은 `register(on, options)` 를 내보낸다. 훅은 `on('event', matcher, ($, e, next) => ...)` — Express 미들웨어 모델이다. 부수효과는 전부 `$` 한 객체의 메서드라, 상위 플러그인이 `$` 에서 속성을 지우면 하위 전부가 그 능력을 잃는다.

내장 mod 넷: `sec-default`, `diff`, `telemetry`, `agents-md`.

게이트는 환경변수 `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` 와 GrowthBook 플래그 `tengu_plugin_hooks_modules` (기본 false).

### 왜 이 확장의 답이 아닌가

**서피스는 맞다.** 훅 하나가 네 서피스에 그려진다.

```ts
export type RenderSurface = 'terminal' | 'desktop' | 'mobile' | 'vscode';
```

`desktop` 은 Claude Desktop 안의 Claude Code 세션이다. 앱이 직접 켠다:

```js
I = a.conversationPlugin === true && !N;
I && (e.env = { ...e.env, CLAUDE_CODE_ENABLE_FUNCTION_HOOKS: "1" })
// [CCD] Passing ${T.length} plugin(s) to SDK
```

**닿는 범위가 안 맞는다.** 이 확장은 렌더러 DOM 전체에 오버레이를 그린다. mod가 닿는 건 엔진의 렌더 사이트뿐이고, 엔진 noun 전체가 이렇다:

```
agent attribution audio clock command config engine env fs http mcp
model plugin process prompt session settings skill store tool turn ui
```

`app` / `window` / `chrome` 이 없다. 사이드바, 작업 디렉터리 pill, 모델·모드 메뉴는 앱 크롬이라 경로가 아예 없다.

**키보드가 닫혀 있다.** 이게 진짜 벽이다.

- 전역 keydown 훅 없음 — `claude-code.d.ts` 12,990줄 전체에서 keybinding 언급은 2군데뿐이다
- `Button.hotkey` — 소문자 한 글자 또는 숫자 하나, 그것도 그 플러그인의 site가 포커스를 쥐고 있는 동안만
- `Button.action` — 엔진이 이미 가진 keybinding 이름(`"app:cycleDiffBase"`)만 받고, 없는 이름은 거부된다. `Ctrl+;` 같은 새 코드를 등록할 방법이 없다
- 포커스 링을 갖는 site는 `Pane` 과 `AbovePrompt`(프롬프트 위 밴드) 둘뿐
- `ClientSurface.onKey` 는 클릭으로 포커스를 준 뒤, 자기 영역 안에서만
- `$.ui.blit` 은 자기가 마운트한 Raster/Image 영역 전용이다. 화면 오버레이가 아니다

**엔진 버튼에 라벨만 붙이는 것도 안 된다.** `ui.render` 훅이 받는 `RenderPropsOf` 는 컴포넌트당 평문 데이터(`text`, `output`, `isExpanded`, `onScreen` …)뿐이라 엔진이 그린 버튼을 열거할 수 없다. 후킹 가능한 컴포넌트도 15개로 고정이다.

### 로컬 실측

최소 mod를 만들어 `--plugin-dir` 로 올리고 `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude -p` 로 돌렸더니 **훅이 불리지 않았다** (모듈에서 `node:fs` 로 쓰게 한 로그 파일이 생기지 않음). 게이트가 환경변수 하나가 아니다:

```js
gqt = () => sBe() && aX()
aX  = () => !Cb() && !qr("hooks") && !hg()
```

비대화형(`-p`)에서는 모듈이 올라오지 않는 것으로 보인다. **이 머신에서 mods 런타임 실동작은 확인하지 못했다.** 위 API 분석은 전부 `mods/types/claude-code.d.ts` 와 `mods/README.md` 기준이다.

---

## 2. 로컬 번들 (ion-dist)

### 먼저, 새로 알아낸 것이 아니다

**이 프로젝트는 2026-08-23에 이미 여기까지 왔다.** 구현 계획서 부록 "왜 Task 1·10·11을 폐기했나"에 `ion-dist/index.html` 에 프로브를 넣고 앱을 재시작한 기록이 있다. 프로브는 실행되지 않았고, DevTools 실행 컨텍스트에서 top 문서 origin이 `claude.ai` 임을 확인했다. 즉 **실증은 이미 되어 있었다.**

정확하지 않았던 건 README 쪽 요약 문장이다.

> Claude Desktop renders **remote `claude.ai`**, not a local bundle. There is no HTML file on disk to add a `<script>` tag to.

앞 절은 맞고 뒤 절은 틀렸다. HTML은 디스크에 있다 — 로드되지 않을 뿐이다. 계획서는 이걸 정확히 적었는데("`ion-dist`는 `app://` 프로토콜의 루트로 등록돼 있을 뿐 현재 로드되지 않고") README가 줄이면서 "없다"가 됐다.

**이번 조사가 실제로 보탠 것은 하나뿐이다: 왜 로드되지 않는가.** 계획서는 "원격을 렌더한다"는 관찰까지였고, 그 분기를 누가 어떤 조건으로 정하는지는 없었다. 아래가 그 답이다.

`Contents/Resources/ion-dist/` 에 180MB짜리 완전한 로컬 SPA 번들이 있고, 앱이 시작 시 프로토콜 핸들러로 서빙한다.

```js
t9n(n.default.join(rgi(), "ion-dist"), c ? () => s.discoveredRendererConfig() ?? c : void 0)
// catch: "Failed to install app:// protocol handler"
```

- `index.html` 실재, CSP meta 없음, 인라인 `<script data-compose-prelude>` 정상 실행
- preload의 신뢰 오리진 allowlist에 `app://localhost` 가 claude.ai와 나란히 있다
- **ion-dist는 app.asar 바깥이다.** `Info.plist` 의 ASAR 무결성 해시는 `Resources/app.asar` 단건만 덮으므로, 여기 손대는 데는 해시 재계산도 plist 편집도 필요 없다

계획서는 이 사실("`ion-dist`는 `ElectronAsarIntegrity` 검증 대상이 아니므로 asar을 안 건드려도 된다")을 **틀린 전제 묶음 안에** 넣어뒀는데, 이 하위 주장 자체는 맞다. 틀렸던 건 "그러니 주입하면 로드된다" 쪽이다.

단, ASAR 무결성과 별개로 `Contents/Resources/` 아래를 건드리면 `_CodeSignature/CodeResources` 봉인이 깨진다. 설계 문서가 이미 기록해 둔 대로 실행 자체는 되지만, 로더가 따로 떠안아야 할 항목이다.

### 그런데 왜 여전히 안 되는가

메인 윈도우 URL은 배포 모드가 정하고, 구현이 정확히 둘이다.

```js
getMainWindowUrl(){ return this.deps.anthropicOriginUrl() }   // 1p → https://claude.ai
getMainWindowUrl(){ return Uu }                               // 3p → var Uu = "app://localhost"
```

분기는 `UQt`(initDeploymentMode) 한 곳, 판정은 병합된 배포 설정뿐이다.

```js
var js = e => !!e.bootstrap?.url && e.bootstrap?.enabled !== !1;
function _De(e){ return e.inference !== void 0 || js(e) || Sc(e) }   // Sc: e.selfHosted !== void 0
```

- 오프라인 폴백이 아니다 (네트워크 상태를 보는 분기가 없다)
- GrowthBook 롤아웃이 아니다 (근처 GB 게이트는 1p direct-MCP 풀 전용)
- CLI 플래그도 환경변수도 아니다
- `deploymentMode` 설정 키는 1p 강제만 가능하고 3P를 켜지는 못한다
- 번들 모드에서는 외부 내비게이션이 차단된다 — `"Blocked bundled-SPA window navigation to …"`

현재 상태 확인: Local Storage 오리진은 `_https://claude.ai` 하나뿐, `IndexedDB/app_localhost_0…` 는 2026-05-04 잔여물, `https_claude.ai_0…` 가 현재. `configLibrary/` 디렉터리는 존재하지 않는다. 전부 1p 모드와 일치한다.

### 켤 수는 있다 — 그런데 쓰면 안 된다

설정 티어 중 local(`~/Library/Application Support/Claude/configLibrary/`)이 **일반 사용자 쓰기 가능**이고 키 화이트리스트 검증만 한다. `inference` / `selfHosted` / `bootstrap.url` 중 하나만 넣으면 3P로 넘어간다. root도 MDM도 필요 없다.

CSP도 막지 않는다. 디스크의 html을 읽어 런타임에 생성하는 구조라 `script-src 'self'` 가 형제 파일을 허용하고, 인라인 블록을 넣으면 그 해시를 읽어 `sha256-` 를 자동으로 추가해 준다. SRI도 없다.

**그런데 3P 모드는 "번들을 렌더하는 모드"가 아니라 실제로 third-party 배포가 되는 것이다.** 앱이 `/api/bootstrap`, `/system_prompts`, `/current_user_access` 를 로컬에서 합성 응답하고 추론을 설정한 공급자로 보낸다. 자격증명이 없으면 `"[custom-3p] 3P mode active (degraded — no valid credentials)"`. claude.ai 계정 사용이 깨진다.

진짜 백엔드를 유지하는 `hybrid-pointer` 변종은 엔터프라이즈 org 엔드포인트(`/v1/desktop/orgs/<uuid>/bootstrap`)를 요구하므로 개인 계정에는 해당이 없다.

E2E 우회(`CLAUDE_E2E_*`)는 `CLAUDE_CDP_AUTH` 가 앱에 하드코딩된 Ed25519 공개키로 서명 검증을 통과해야 하고 유효기간이 5분이라 위조할 수 없다.

### 외부 주입 경로는 오히려 조여졌다

```
codesign flags=0x10000(runtime)
entitlements: get-task-allow ✗  disable-library-validation ✗  allow-dyld-environment-variables ✗
차단 시작 플래그: remote-debugging-port, remote-debugging-pipe,
  ignore-certificate-errors, host-resolver-rules, host-rules,
  disable-web-security, log-net-log, net-log-capture-mode,
  ssl-key-log-file, renderer-cmd-prefix, …
```

---

## 결론

DevTools 스니펫이 여전히 유일한 경로다. 바뀐 것은 **이유**이지 결론이 아니다.

Mods 쪽이 열리려면 전역 key 훅이나 커스텀 chord 등록이 필요하다. 그걸 추적하는 이슈는 없다 — [anthropics/claude-code#91870](https://github.com/anthropics/claude-code/issues/91870) 은 Mods 전반 스레드이지 이 기능 요청이 아니다. 그게 생기면 Claude Code 세션 UI 한정으로는 의미가 생기지만, 그때도 이 확장의 이식이 아니라 별개의 더 작은 물건이다.

## 확인하지 않은 것

- mods 런타임의 실동작 (대화형 세션에서 재확인 필요)
- `_CodeSignature/CodeResources` 봉인이 깨진 뒤 Gatekeeper 재검증(격리 속성이 붙거나 앱이 업데이트될 때)이 어떻게 되는지. 설계 문서가 "실행 자체는 됨"까지는 기록해 뒀지만 그 이후는 모른다 — `/Applications/Claude.app` 을 수정하지 않았다
- 3P 모드 전환 자체 (코드 경로로만 확인했고 실제로 넘겨보지 않았다)
