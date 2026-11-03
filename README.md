# 카카오톡 배너 스튜디오

macOS에서 카카오톡 하단 배너를 개인화하는 비공식 앱입니다.

`KakaoBanner.xcodeproj`를 Xcode로 열고 앱과 시스템 확장 타깃에 본인의 서명 팀을 설정합니다. 실제 배너 적용에는 macOS 네트워크 확장 승인과 앱의 로컬 인증서 설정이 필요합니다.

보관함에서 **커뮤니티**를 열면 `main` 브랜치의 `community/banners.json`을 읽습니다. 배너를 선택하고 미리보기에서 **카카오톡 재시작**을 누르면 적용합니다.

커뮤니티 배너를 추가하려면 직접 만들었거나 공개 배포가 허용된 4:1 PNG, JPEG 또는 GIF를 `community/images/`에 넣고, `banners.json`에 고유한 `id`, `title`, `author`, `image`를 추가해 PR을 열어 주세요. 파일 크기는 최대 8MB입니다.
