# Mac에서 직접 실행하는 방법

소스 코드를 Xcode에서 직접 빌드하는 방법입니다. 설치 파일을 사용하려면 [GitHub Releases에서 DMG를 다운로드](https://github.com/GwonHyeok/kakao-banner-studio/releases/latest)하세요. 시작하기 전에 [테스트 환경](../README.md#requirements)을 확인하세요.

## Xcode에서 빌드하기

1. 저장소의 **Code → Download ZIP**에서 소스를 받고 압축을 풉니다.
2. Xcode에서 `KakaoBanner.xcodeproj`를 열고 **KakaoBanner** 스킴과 **My Mac**을 선택합니다.
3. **KakaoBanner**와 **BannerProxy** 타깃의 **Signing & Capabilities**에서 같은 Apple Developer 팀을 선택하고 **Automatically manage signing**을 켭니다. 두 타깃 모두 Network Extensions 권한이 포함된 macOS 개발용 프로비저닝 프로필이 필요합니다.
4. 본인 팀에서 빌드할 경우 두 타깃의 **Bundle Identifier**를 본인 팀에 등록할 수 있는 값으로 변경합니다. 확장에는 앱 ID 뒤에 `.proxy`를 붙이고, [ProxyAccess.swift](../App/Infrastructure/ProxyAccess.swift)의 `identifier`에도 같은 확장 ID를 지정합니다.
5. **Product → Build**(⌘B)를 실행합니다. **Products**에서 빌드된 앱을 Finder로 열어 **응용 프로그램** 폴더에 복사하고, 그곳에서 실행합니다.

## 첫 실행에서 권한 설정하기

1. 앱에서 **확장 설정 시작**을 누릅니다. macOS에서 네트워크 확장 승인을 요청하면 시스템 설정에서 허용합니다.
2. 앱으로 돌아와 **인증서 설정**을 누르고 macOS 확인을 완료합니다.
3. 권한을 다시 설정하려면 사이드바에서 **네트워크 및 인증서**를 엽니다.

설정을 마쳤다면 [배너 바꾸기](../README.md#배너-바꾸기)를 따라 적용하세요.
