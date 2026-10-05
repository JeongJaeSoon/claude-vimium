# 업데이트 후 접근성 권한을 유지하는 배포

v1.1.0부터 Homebrew 배포는 CI에서 Developer ID로 서명하고 Apple 공증을 받은 universal 앱을 설치하는 경로를 사용합니다. 기존 source 배포에서 처음 전환할 때는 접근성 권한을 다시 허용해야 할 수 있습니다. 동일한 서명 기준을 사용하는 다음 버전으로 실제 업그레이드했을 때 권한이 유지되는지에 대한 실기기 검증은 아직 완료되지 않았습니다.

## 배포 방식

릴리스 CI에서 universal 앱을 빌드하고 Developer ID Application으로 서명한 뒤 Apple에 공증을 제출합니다. 공증 티켓을 앱에 붙이고 `hintvim-VERSION-macos-universal.tar.gz`로 배포합니다. signed formula는 앱을 다시 빌드하거나 서명하지 않고 그대로 설치합니다. 기존 formula 이름과 `brew upgrade hintvim` 명령은 유지합니다.

동일한 `CFBundleIdentifier`와 Developer ID 서명 기준을 유지해야 합니다. 기존 ad-hoc 앱에서 처음 전환할 때는 접근성 권한을 한 번 더 허용해야 할 수 있습니다. 그 이후의 권한 유지 여부는 두 개의 실제 서명된 버전을 업그레이드하며 검증해야 합니다. 공증만으로 권한 유지가 보장되지는 않습니다.

## 관리자 준비

Apple Developer Program 가입 및 Developer ID Application 인증서와 개인 키가 필요합니다. 인증서는 개인 키를 포함한 암호화된 `.p12`로 내보냅니다. GitHub Actions에는 다음 repository secrets를 설정합니다. 비밀값은 이 문서, 이슈, PR, 채팅이나 저장소에 넣지 않습니다.

| Secret | 용도 |
|---|---|
| `APPLE_SIGNING_CERTIFICATE_P12_BASE64` | `.p12`의 base64 내용 |
| `APPLE_SIGNING_CERTIFICATE_PASSWORD` | `.p12` 내보내기 암호 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: 이름 (TEAMID)` 인증서 이름 |
| `APPLE_TEAM_ID` | Apple 개발자 팀 ID |
| `APPLE_NOTARIZATION_APPLE_ID` | 공증에 사용하는 Apple 계정 |
| `APPLE_NOTARIZATION_APP_PASSWORD` | 해당 계정의 앱 전용 암호 |

여섯 값이 모두 없으면 기존 source 릴리스를 유지합니다. 일부만 설정됐으면 릴리스는 실패합니다. 서명 또는 공증에 실패해도 signed 배포를 source 빌드로 대체하지 않습니다.

## 릴리스 및 확인

1. `plugin/.claude-plugin/plugin.json`, `packaging/hintvim.rb`, `packaging/hintvim-signed.rb`, `CHANGELOG.md`의 버전을 맞춥니다. 기존 공개 태그를 재사용하지 않습니다.
2. CI 통과 후 새 태그를 올립니다. 릴리스에서 signature, 팀 ID, 공증, staple 검증을 확인합니다.
3. `TAP_TOKEN`이 등록되어 있으면 workflow가 signed formula를 공개 tap에 반영합니다. 없으면 macOS에서 동일 팀 ID로 검증하며 `sh scripts/publish-tap.sh vX.Y.Z signed`를 실행합니다.
4. 공개 formula의 URL과 SHA256을 확인하고 `brew upgrade hintvim`, `brew test hintvim`, `hintvim setup`을 실행합니다.
5. 첫 signed 설치에서 접근성을 허용한 뒤, 동일 팀·bundle ID의 다음 signed 버전으로 업그레이드합니다. 앱 재시작 후 `hintvim doctor`, `Ctrl+;`, 라벨 선택, 키 입력 차단을 확인합니다. 접근성 설정을 다시 만지지 않아도 작동하는지 기록합니다.

기존 source formula CI와 모의 서명 테스트는 배포 경로를 검증할 뿐 실제 Apple 서명·공증이나 TCC 권한 유지의 증거가 아닙니다.

참고: [Apple의 코드 식별 기준](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [macOS 소프트웨어 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
