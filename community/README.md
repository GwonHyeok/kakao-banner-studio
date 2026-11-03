# 커뮤니티에 배너 공유하기

배너를 공유하려면 이미지 파일과 목록 항목을 같은 PR에 넣어 주세요. PR이 `main`에 병합되면 앱의 **보관함 → 커뮤니티**에 표시됩니다.

## 1. 배너 준비

- 가로세로 비율 **4:1**인 PNG, JPEG 또는 GIF를 준비합니다. 예를 들어 800×200px을 사용할 수 있습니다.
- 파일은 **8MB 이하**여야 합니다. 최대 크기는 8192×2048px입니다.
- 직접 만들었거나 공개 배포가 허용된 이미지를 사용하고, 공개할 수 있는 제작자 이름을 적어 주세요.

## 2. 이미지와 목록 등록

1. [저장소 포크](https://github.com/GwonHyeok/kakao-banner-studio/fork)를 만들고 포크에서 작업 브랜치를 만듭니다.
2. 포크의 `community/images/`에 **Add file → Upload files**로 이미지를 올립니다. 파일명은 영문자, 숫자, 하이픈, 밑줄을 사용하고 확장자는 소문자로 적습니다.
3. 같은 브랜치의 [목록 파일](banners.json)을 편집해 기존 배열에 항목을 하나 추가합니다. `id`는 기존 항목과 겹치지 않게 정합니다.

```json
{
  "id": "morning-sky",
  "title": "아침 하늘",
  "author": "공개할 제작자 이름",
  "image": "images/morning-sky.png"
}
```

## 3. PR 보내기

[PR 비교 화면](https://github.com/GwonHyeok/kakao-banner-studio/compare)에서 **compare across forks**를 선택합니다. 대상은 `GwonHyeok/kakao-banner-studio`의 `main`, 비교 대상은 본인의 포크와 작업 브랜치로 지정합니다. **Create pull request**를 누른 뒤 자동으로 채워지는 양식에 배너 이름과 이미지 경로를 적고 체크리스트를 확인해 제출합니다.

## 배너 출처

- 뒤뚱뒤뚱 오리. Drummyfish의 [오리 걷기 GIF](https://commons.wikimedia.org/wiki/File:Cartoon_steamer_duck_walking_animation.gif)를 4:1 배너에 맞게 배치했습니다. 원본은 CC0 1.0입니다.
