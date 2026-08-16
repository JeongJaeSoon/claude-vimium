# 다음 단계 절차

작성: 2026-08-17

## 지금 어디까지 왔나

기능 구현은 전부 끝났고 사람이 수동 검증 2회를 통과시켰다. 남은 것은 **설치 경로뿐**이다.

| | 상태 |
|---|---|
| 저장소 | github.com/JeongJaeSoon/claude-vimium (private, MIT) |
| 브랜치 | `feat/hint-mode` — 커밋 15개, 전부 push 완료 |
| PR | #1 (open). 머지하지 않는다 — 설치 경로가 없으면 쓸 수 없는 코드가 `main`에 들어간다 |
| 워킹트리 | 깨끗함 |
| 테스트 | 3개 스위트 전부 통과 |

남은 작업은 세 개다: **CSP 검증 → `install.sh` + README → LaunchAgent 복구 검증.**

## 1단계: CSP 검증

`<script src="/claude-vimium.js">`가 앱의 CSP에 막히는지 확인한다. 이 결과가 `install.sh`의 절반을 결정하므로 다른 작업보다 먼저 한다.

> 참고: 별도로 진행한 claude-ext 설계 세션이 "claude.ai 페이지엔 CSP 없음"을 실측했다. 통과할 가능성이 높지만, 그쪽은 `app://` 스킴으로 확인했고 여기는 `ion-dist` 루트 상대 경로라 경로 해석이 다를 수 있다. 그대로 확인한다.

### 1-1. 프로브 배치

```bash
DIST="/Applications/Claude.app/Contents/Resources/ion-dist"
printf 'console.log("[claude-vimium] CSP OK");\n' > "$DIST/claude-vimium-probe.js"
cp "$DIST/index.html" "$DIST/index.html.probe.bak"
sed -i '' 's#</body>#<script src="/claude-vimium-probe.js"></script></body>#' "$DIST/index.html"
grep -c 'claude-vimium-probe' "$DIST/index.html"
```

마지막 줄이 **`1`** 을 출력해야 한다. `0`이면 주입이 안 된 것이니 다음으로 넘어가지 말 것.

### 1-2. 앱 재시작

**여기서 지금 세션이 끊긴다.** Claude Desktop을 `Cmd+Q`로 완전히 종료하고 다시 연다.

### 1-3. 콘솔 확인

`Cmd+Alt+I` → Console 탭.

| 보이는 것 | 결론 |
|---|---|
| `[claude-vimium] CSP OK` | `INJECTION_MODE = "src"` — 계획대로 외부 스크립트 참조 |
| `Refused to load the script ...` | `INJECTION_MODE = "inline"` — 인라인 주입으로 폴백 필요 |
| 둘 다 없음 | 주입 자체가 실패. 1-1의 `grep` 결과를 다시 확인 |

콘솔이 시끄러우면 필터에 `claude-vimium` 또는 `Refused`를 입력한다.

### 1-4. 원복

**결과를 확인한 직후 반드시 실행한다.** 프로브를 남겨두면 나중에 `install.sh`가 만드는 백업이 오염된다.

```bash
DIST="/Applications/Claude.app/Contents/Resources/ion-dist"
mv "$DIST/index.html.probe.bak" "$DIST/index.html"
rm -f "$DIST/claude-vimium-probe.js"
grep -c 'claude-vimium' "$DIST/index.html" || true
```

마지막 줄이 **`0`** 이어야 한다. 앱이 검증 전 상태로 완전히 돌아갔다는 뜻이다.

### 1-5. 문제가 생기면

| 증상 | 대처 |
|---|---|
| 앱이 안 켜진다 | `ion-dist`는 무결성 검증 대상이 아니라 이걸로 앱이 죽지는 않는다. 그래도 안 켜지면 1-4의 원복 명령을 실행하고 다시 연다 |
| 백업 파일을 잃었다 | Claude Desktop을 재설치하면 `ion-dist`가 통째로 새로 깔린다. 사용자 데이터는 `~/Library/Application Support/Claude`에 있어 영향받지 않는다 |
| `sed`가 아무것도 안 바꿨다 | `</body>`가 없는 것이다. `grep -c '</body>' "$DIST/index.html"`로 확인 |

## 2단계: 새 세션에서 재개

앱을 다시 켠 뒤 Claude Code 새 세션을 열고, 아래를 **그대로 붙여넣는다.** `[여기에 결과]` 부분만 1-3에서 본 것으로 바꾼다.

```
claude-vimium 프로젝트를 이어서 진행한다. 작업 위치는 ~/workspace/project/claude-vimium, 브랜치는 feat/hint-mode다.

## CSP 검증 결과

INJECTION_MODE = [여기에 결과: "src" 또는 "inline"]
콘솔에서 실제로 본 것: [여기에 결과: 예 - [claude-vimium] CSP OK 가 찍혔다]

## 지금까지의 상황

기능 구현(힌트 모드, 라벨 입력, 스크롤, 설정 화면, 도움말)은 전부 끝났고 사람이 수동 검증 2회를 통과시켰다. Node 테스트 3개 스위트도 전부 통과한다. PR #1이 열려 있고 머지하지 않은 상태다 — 설치 경로가 없으면 쓸 수 없는 코드가 main에 들어가기 때문이다.

전체 이력은 .superpowers/sdd/2026-08-17-claude-vimium/progress.md 에 한 줄씩 남아 있다. 커밋 범위, 리뷰 결과, 파킹한 항목, 사람이 통과시킨 검증이 전부 거기 있다.

## 남은 일

계획서 docs/superpowers/plans/2026-08-17-claude-vimium.md 의 Task 10과 Task 11이다.

- Task 10: install.sh + README. 위 INJECTION_MODE에 따라 inject() 구현이 갈린다. "inline"이면 계획서 Task 10의 Step 2에 있는 대체 코드를 쓴다
- Task 11: LaunchAgent 복구 검증. 주입을 지운 뒤 자동 재주입되는지, 무한 루프가 없는지 확인한다

superpowers:subagent-driven-development 로 진행하되, DOM이나 앱 재시작이 필요한 검증 단계는 서브에이전트가 할 수 없으니 사람에게 넘겨야 한다. 그전까지 그렇게 진행해 왔다.

## 이 프로젝트에서 이미 확인된 사실 (재조사 불필요)

- ion-dist는 ElectronAsarIntegrity 검증 대상이 아니다. app.asar만 헤더 해시로 검증되고, 그 해시는 지금 Info.plist와 일치한다(앱 원본 상태)
- --remote-debugging-port로 앱을 띄우면 즉시 종료된다. CDP 경로는 배제됐다
- 앱 번들의 클래스명은 해시되어 있어 셀렉터 하드코딩은 금지다
- 한글 자판에서 e.key는 자모를 반환하므로 e.code 폴백이 필요하고, macOS 한글 IME는 preventDefault를 뚫고 조합을 시작한다. 둘 다 이미 해결되어 있다
```

## 3단계: Task 10 — `install.sh` + README

계획서의 Task 10에 전체 스크립트가 들어 있다. 요점만:

- 서브커맨드: `install`(기본) / `status` / `uninstall`, 플래그 `--no-auto`
- `index.html`을 `index.html.claude-vimium.bak`으로 백업하되 **기존 백업이 있으면 덮어쓰지 않는다** (패치된 파일을 백업해 원본을 잃는 것 방지)
- 중복 주입 금지
- LaunchAgent는 **기본 활성**, `--no-auto`로 끌 수 있음
- 무엇을 어디에 설치했는지 명시적으로 출력

`INJECTION_MODE`가 `"inline"`이면 계획서 Task 10 Step 2의 대체 `inject()`를 쓰고, `MARKER`를 `data-claude-vimium`으로 바꾸며 `</html>` 중복에 주의한다.

README에는 설치법, 키 바인딩 표, **LaunchAgent가 무엇을 하는지**, 제거법, 알려진 제약(앱 업데이트 시 주입 소실, `codesign --verify` 실패, macOS 전용), 테스트 실행법을 적는다.

## 4단계: Task 11 — LaunchAgent 복구 검증

앱 업데이트를 기다릴 수 없으므로 흉내 낸다: 백업으로 `index.html`을 되돌려 주입을 지우고, 5초 뒤 재주입되었는지 확인한다. 이어서 10초 더 두고 `<script>` 태그가 **하나만** 있는지 본다 — 무한 루프가 없다는 확인이다.

## 그다음

Task 11까지 끝나면 v1이 완성된다. 그때 PR #1을 머지하고, 저장소를 public으로 전환할지 결정하면 된다.

claude-ext(확장 템플릿)는 별개 프로젝트다. 완성되면 claude-vimium을 그 위의 확장으로 옮길 수 있고, 코드는 바뀌지 않는다 — `./install.sh uninstall` 후 등록만 하면 된다. **둘을 동시에 설치하지 말 것.**
