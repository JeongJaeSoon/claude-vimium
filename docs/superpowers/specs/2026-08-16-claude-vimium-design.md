# claude-vimium 설계

작성일: 2026-08-16

## 1. 목적

Claude Desktop(`Claude.app`)에서 마우스 없이 UI를 조작할 수 있게 하는 확장. Vimium이 브라우저에서 하는 일을 Claude Desktop에서 한다.

핵심 가치는 **화면의 임의 요소를 키보드로 클릭하는 것**이다. 앱은 이미 `Cmd+K`(커맨드 팔레트), `Cmd+1…9`(세션 점프), `Cmd+Shift+F`(파일 브라우저) 같은 단축키를 제공하지만, 단축키가 배정되지 않은 요소 — 작업 디렉토리 pill, 모드/모델 메뉴, 메시지별 액션 버튼 — 는 마우스로만 닿을 수 있다. 힌트 모드가 그 공백을 전부 메운다.

GitHub에 공개해 누구나 설치할 수 있게 한다.

## 2. 확인된 플랫폼 사실

로컬 `Claude.app`을 직접 분석해 확인한 내용이다. 구현 시 재조사 불필요.

| 항목 | 내용 |
|---|---|
| UI 번들 | `/Applications/Claude.app/Contents/Resources/ion-dist/` — 평범한 SPA 빌드 |
| 진입점 | `ion-dist/index.html` (31KB). 인라인 `<script>`가 이미 존재하고 `</body>`는 파일 끝에 정확히 1개 |
| 웹 루트 | 에셋이 `/assets/v1/...` 절대경로 → `ion-dist`가 루트 |
| 무결성 검증 | `Info.plist`의 `ElectronAsarIntegrity`는 `Resources/app.asar` **하나만** SHA256 검증. `ion-dist/`는 대상 아님 |
| 쓰기 권한 | `index.html`은 `dev-soon:staff` 소유, sudo 불필요 |
| DevTools | `Cmd+Alt+I`로 열림. 콘솔/Snippets에서 DOM 조작이 실제 동작함을 확인 |
| CDP 주입 | **차단됨.** `app.asar`에 `hae(process.argv) && !p9() && process.exit(1)` — `--remote-debugging-port` / `--remote-debugging-pipe` 감지 시 서명된 개발자 빌드가 아니면 즉시 종료 |
| 코드서명 | 리소스 수정 시 `codesign --verify` 실패. `app.asar` 무결성과는 별개라 실행 자체는 됨 |
| 클래스명 | 해시되어 있음 → 셀렉터 하드코딩 금지 |

Vencord/BetterDiscord가 asar을 패치해야 하는 것과 달리, 무결성 검증 범위가 `app.asar`로 한정되어 있어 `ion-dist`만 건드리면 된다. 이것이 이 플랫폼의 결정적 이점이다.

## 3. 범위

### MVP에 포함

- 리더 키로 힌트 모드 진입, 클릭 가능 요소에 라벨 표시, 라벨 키 입력으로 클릭
- 힌트 모드 중 `j`/`k`/방향키 스크롤
- 설정 화면 (리더 키, 힌트 문자셋, 스크롤 양)
- 설치 / 제거 / 상태 확인 / 자동 복구

### 제외

- 플러그인 API, 설정 UI 프레임워크 등의 추상화 — 확장이 2개 이상 생기기 전에는 만들지 않는다
- 앱에 이미 단축키가 있는 기능(커맨드 팔레트, 세션 점프, 파일 브라우저)의 재구현
- 메시지 단위 이동/복사 — DOM에서 메시지 경계를 잡아야 해서 앱 업데이트에 가장 취약하다. 힌트 모드로 상당 부분 대체된다
- 작업 디렉토리 전용 전환 커맨드 — 폴더 pill이 힌트로 잡히므로 중복

## 4. 저장소 구조

`~/workspace/project/claude-vimium`에 새 git 저장소로 만든다.

```
claude-vimium/
├── src/claude-vimium.js   # 확장 본체 (단일 파일, 의존성 0)
├── install.sh             # 설치 / 제거 / 상태 / LaunchAgent 등록
├── docs/
└── README.md
```

빌드 스텝과 외부 의존성을 두지 않는다. 힌트 모드와 스크롤을 합쳐도 300줄 안쪽이라 번들러가 벌어들이는 것이 없고, 남의 앱 번들을 수정하는 도구인 만큼 소스가 그대로 읽히는 편이 신뢰에 유리하다. 코드가 실제로 커지면 그때 TypeScript + 번들러로 옮긴다.

## 5. 확장 본체 (`src/claude-vimium.js`)

### 5.1 모드와 키

리더 키(기본 `Ctrl+Space`)를 누르면 **즉시 힌트 모드**에 진입한다. Vimium처럼 `f`를 한 번 더 누르지 않는다 — 리더 키가 이미 모드 전환이므로 힌트를 바로 띄우는 편이 키를 하나 덜 누른다.

| 키 | 동작 |
|---|---|
| 리더 키 (기본 `Ctrl+Space`) | 힌트 모드 진입 |
| 라벨 문자 | 해당 요소 클릭 후 모드 종료 |
| `j` / `k` / `↓` / `↑` | 스크롤 (모드 유지) |
| `,` | 설정 화면 열기 |
| `Esc` | 모드 종료 |

리더 키가 필요한 이유: Claude Desktop은 composer에 거의 항상 포커스가 있어서, 웹 확장식 단일 키 트리거가 그대로는 글자 입력으로 들어간다. 모드 방식은 앱/OS 기본 단축키와도 충돌하지 않는다.

키 이벤트는 `keydown`을 캡처 단계에서 가로채고, 모드 활성 중에는 `preventDefault()` + `stopPropagation()`으로 앱에 전달되지 않게 한다.

### 5.2 힌트 대상 탐색

역할 기반 셀렉터로 후보를 모은다:

```
button, a[href], input, textarea, select,
[role="button"], [role="menuitem"], [role="tab"], [role="link"],
[tabindex]:not([tabindex="-1"]), [contenteditable="true"]
```

필터:

- 뷰포트 안에 있을 것
- `getBoundingClientRect()`의 width/height가 0이 아닐 것
- `display: none`, `visibility: hidden`, `opacity: 0`이 아닐 것
- `disabled`가 아닐 것
- 중첩된 후보는 가장 안쪽 것만 남길 것

클래스명을 일절 참조하지 않으므로 앱 업데이트로 번들이 재빌드돼도 깨지지 않는다. 이것이 셀렉터 하드코딩 대비 유일하게 중요한 설계 선택이다.

### 5.3 라벨 생성

홈로우 문자셋(기본 `asdfghjkl`)에서 뽑는다. 후보 수가 문자셋 크기를 넘으면 2글자로 늘린다. 접두사 충돌이 없도록 생성한다 — 즉 1글자 라벨과 그 글자로 시작하는 2글자 라벨이 동시에 존재하지 않아야 한다.

라벨 오버레이는 `position: fixed`로 요소 좌상단에 그리고, `z-index`는 앱 최상단 위로, `pointer-events: none`으로 클릭을 방해하지 않게 한다.

부분 입력 시 매칭되지 않는 라벨은 즉시 숨긴다.

### 5.4 클릭 실행

라벨이 확정되면 대상 요소에 `click()`을 호출한다. React 합성 이벤트는 네이티브 `click` 이벤트를 위임 방식으로 받으므로 대부분 그대로 동작한다. 동작하지 않는 요소가 발견되면 `dispatchEvent(new MouseEvent('click', {bubbles: true}))` 폴백을 검토한다.

단, `input` / `textarea` / `[contenteditable="true"]`는 클릭이 아니라 `focus()`한다. 이들 요소에서 사용자가 원하는 것은 클릭이 아니라 커서 진입이다.

### 5.5 리렌더 대응

React가 리렌더하면 오버레이가 사라질 수 있다. 오버레이는 앱 DOM 트리 바깥(`document.body` 직속의 자체 컨테이너)에 그려서 앱 리렌더의 영향을 받지 않게 한다.

### 5.6 설정

`localStorage`에 저장한다. 파일 접근이 필요 없어 설치 스크립트가 다룰 대상이 줄어든다.

| 항목 | 기본값 |
|---|---|
| 리더 키 | `Ctrl+Space` |
| 힌트 문자셋 | `asdfghjkl` |
| 스크롤 양 | 60px |

설정 화면은 힌트 모드에서 `,`로 연다. 확장이 자체 스타일로 그리는 모달 오버레이이며 앱 DOM 구조에 의존하지 않는다. 리더 키 입력은 실제 키 입력을 받아 기록하는 방식으로 한다.

## 6. 설치 (`install.sh`)

```
./install.sh            # 설치 (LaunchAgent 포함)
./install.sh status     # 설치 여부 + 앱 버전 확인
./install.sh uninstall  # 원복 (LaunchAgent 제거 포함)
./install.sh --no-auto  # LaunchAgent 없이 설치
```

설치 동작:

1. `index.html`을 `index.html.claude-vimium.bak`으로 백업 (기존 백업이 있으면 덮어쓰지 않는다 — 패치된 파일을 백업해 원본을 잃는 것을 막는다)
2. `src/claude-vimium.js`를 `ion-dist/claude-vimium.js`로 복사
3. `</body>` 직전에 `<script src="/claude-vimium.js"></script>` 삽입. 이미 삽입되어 있으면 중복 주입하지 않는다
4. LaunchAgent 등록 (`--no-auto`가 아닌 경우)
5. 무엇을 어디에 설치했는지 명시적으로 출력

### 6.1 앱 업데이트 대응

앱이 업데이트되면 `ion-dist`가 통째로 교체되어 주입이 조용히 사라진다. LaunchAgent가 이를 감지해 재주입한다.

감지 방식은 **`WatchPaths`로 `ion-dist/index.html`을 감시**한다. 앱 업데이트로 파일이 교체되면 LaunchAgent가 깨어나 주입 여부를 확인하고, 없으면 다시 넣는다. 주기적 폴링(`StartInterval`)보다 정확하고 idle 비용이 없다. `RunAtLoad`도 함께 켜서 로그인 시 한 번 확인한다.

우리가 패치할 때도 `WatchPaths`가 트리거되지만, 이미 패치된 상태에서는 재주입이 no-op이므로 한 번 더 돌고 멈춘다. 무한 루프가 되지 않는다.

LaunchAgent를 **기본 활성**으로 둔다. "한 번 설치하면 이후 신경 쓰지 않는다"가 목표인데, 이를 달성하는 유일한 수단을 옵트인에 숨겨두면 대부분의 사용자가 목표 상태에 도달하지 못한다. 대신 설치 중 무엇을 등록하는지 출력하고, `--no-auto`로 끌 수 있게 하며, README에 LaunchAgent의 동작을 명시한다.

### 6.2 CLI 없는 설치에 대하여

확장이 사는 렌더러는 파일시스템에 쓸 수 없다. 따라서 확장이 자기 자신을 설치·재설치할 방법은 없으며, 앱 바깥의 무언가가 반드시 한 번은 실행되어야 한다. "CLI 없이"의 현실적 목표는 **최초 1회만**이고, LaunchAgent가 그 이후를 담당한다.

GUI 인스톨러를 먼저 만들지 않는 이유:

- 서명·공증 없는 `.pkg` / `.command`는 Gatekeeper에 막혀 "우클릭 → 열기" 안내가 필요하다. `curl | sh` 한 줄보다 마찰이 크다
- 서명하려면 Apple Developer Program(연 $99)이 필요하다
- 남의 앱 번들을 수정하는 도구는 초기 사용자에게 스크립트가 그대로 읽히는 편이 신뢰를 얻는다
- 순서상 `install.sh`가 안정화되어야 GUI가 그것을 감쌀 수 있다

v2에서 `install.sh`를 호출하는 더블클릭용 `.command` 래퍼를 얹는다. 몇 줄이라 나중에 붙여도 비용이 없다.

## 7. 에러 처리

| 상황 | 처리 |
|---|---|
| 힌트 대상이 0개 | "힌트 대상 없음" 토스트. 조용한 no-op으로 두면 앱 구조 변경으로 확장이 죽은 것인지 진짜 요소가 없는 것인지 구분할 수 없다 |
| `index.html`이 이미 패치됨 | 중복 주입하지 않고 스크립트 파일만 갱신 |
| 백업 파일이 이미 존재 | 덮어쓰지 않는다 (원본 보존) |
| `Claude.app`을 찾을 수 없음 | 명확한 에러 메시지 후 종료 |
| 설정 값이 손상됨 | 기본값으로 폴백하고 콘솔에 경고 |

## 8. 검증

- **자체 검사**: 라벨 생성과 요소 필터는 순수 함수다. `assert` 기반 자체 검사를 붙인다. 특히 라벨 접두사 충돌 없음을 검사한다
- **수동 체크리스트**: DOM 통합(힌트 표시, 클릭 실행, 스크롤, 설정 저장, 리렌더 후 동작)은 수동 확인
- **설치 검증**: `install.sh status`로 설치 상태를 확인할 수 있게 한다

테스트 프레임워크는 도입하지 않는다.

## 9. 미검증 리스크

**CSP가 `<script src="/claude-vimium.js">`를 허용하는지 확인되지 않았다.** `app.asar`에 host allowlist 기반으로 `script-src` 디렉티브를 구성하는 코드가 있으나, 로컬 앱 스킴에서 로드되는 스크립트가 허용되는지는 실행해봐야 안다.

**이것을 구현 1단계로 둔다.** 막히면 `install.sh`가 `<script src>` 대신 인라인 `<script>`로 파일 내용을 직접 삽입하는 방식으로 폴백한다. 여기서 결과가 갈리면 설치 스크립트의 상당 부분이 바뀌므로 다른 작업보다 먼저 확인해야 한다.

## 10. 로드맵

- **v1**: 힌트 모드 + 스크롤 + 설정 화면 + `install.sh` (LaunchAgent 포함)
- **v2**: 더블클릭용 `.command` 래퍼
- **이후**: 확장이 2개 이상 생기면 그때 로더 구조를 검토한다. 그전에는 만들지 않는다
