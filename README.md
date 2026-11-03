# 카카오톡 배너 스튜디오

Mac용 카카오톡 채팅 목록 하단에 원하는 배너를 표시하는 비공식 앱입니다. 광고를 비우거나, 카카오톡 배경에 맞추거나, 내 이미지나 커뮤니티 배너로 바꿀 수 있습니다.

## Requirements

아래 환경에서 배너 적용을 테스트했습니다. 다른 환경은 호환 여부를 확인하지 않았습니다.

| 항목 | 테스트 환경 |
| --- | --- |
| Mac | Apple Silicon (arm64) |
| 운영체제 | macOS 27.2 (빌드 26B123) |
| 카카오톡 | Mac용 26.9.0 (빌드 2006) |

## 시작하기

현재 GitHub에는 소스 코드가 공개되어 있으며 설치 파일은 준비 중입니다.

- [Mac에서 실행하는 방법](docs/getting-started.md)에서 Xcode 빌드와 첫 권한 설정을 따라 할 수 있습니다.
- [커뮤니티에 배너 공유하는 방법](community/README.md)에서 이미지 등록과 PR 제출 순서를 확인할 수 있습니다.

## 배너 바꾸기

1. **기본 프리셋**에서 **빈 배너** 또는 **카카오톡 일체형**을 선택합니다. **커뮤니티**에서 공유 배너를 고르거나, 상단의 **이미지 추가**로 PNG, JPEG, GIF를 불러올 수도 있습니다.
2. 오른쪽 미리보기에서 배너를 확인합니다.
3. 미리보기의 **카카오톡 재시작**을 누릅니다. 카카오톡이 다시 열리면 하단 배너에 적용됩니다.

**빈 배너**는 하단 공간을 연회색으로 비워 둡니다. **카카오톡 일체형**은 라이트 모드의 사이드바와 본문 색을 배너까지 이어줍니다. 직접 불러온 이미지는 이 Mac에 저장됩니다.

## DMG 빌드와 배포

설치용 DMG를 열고 **카카오톡 배너 스튜디오**를 **Applications**로 드래그합니다. 응용 프로그램에서 앱을 열고 첫 실행 안내에 따라 네트워크 확장과 인증서를 설정합니다.

개발용 서명으로 설치 이미지 구성을 확인하려면 다음 명령을 실행합니다.

```sh
./scripts/build-dmg.sh --local /tmp/KakaoBannerStudio-local.dmg
```

프로비저닝 프로필 원본은 저장소 밖의 개인 폴더에 보관하고, 빌드할 때 `APP_PROFILE`과 `PROXY_PROFILE`로 경로를 전달합니다. 서명 개인 키와 공증 자격 증명은 키체인에서 관리합니다. Git에는 권한을 선언하는 `.entitlements`와 빌드 스크립트를 커밋하고, GitHub Releases에는 공증을 마친 DMG를 첨부합니다. DMG 안의 앱과 확장에는 빌드 과정에서 각 프로필이 내장됩니다.

공개 배포용 빌드에는 같은 Apple Developer 팀의 **Developer ID Application** 서명 인증서와 앱 및 시스템 확장 각각의 **Developer ID 프로비저닝 프로필**이 필요합니다. 두 프로필에 `app-proxy-provider-systemextension` 권한이 있어야 합니다. 공증 자격 증명은 `xcrun notarytool store-credentials`로 키체인에 등록합니다.

```sh
DEVELOPER_ID_IDENTITY='Developer ID Application: 조직명 (팀 ID)' \
APP_PROFILE="$HOME/Library/Application Support/KakaoBannerStudio/Signing/Kakao_Banner_Studio_Developer_ID.provisionprofile" \
PROXY_PROFILE="$HOME/Library/Application Support/KakaoBannerStudio/Signing/Kakao_Banner_Studio_Proxy_Developer_ID.provisionprofile" \
NOTARY_PROFILE=키체인-프로필-이름 \
./scripts/build-dmg.sh --release /tmp/KakaoBannerStudio.dmg
```

공증과 티켓 검증을 통과한 DMG는 GitHub Releases에 첨부합니다. 태그는 배포할 소스 커밋에 맞춥니다.

```sh
gh release create v0.0.1 /tmp/KakaoBannerStudio.dmg \
  --repo GwonHyeok/kakao-banner-studio --draft --generate-notes
```
