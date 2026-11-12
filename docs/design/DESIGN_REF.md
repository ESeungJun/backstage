# 디자인 레퍼런스

## Backstage · 실행 중인 프로그램(CPU 캐릭터) — 2026-11-12

| 레퍼런스 | 좋은 점 | 가져온 것 / 피할 것 |
|---|---|---|
| 1차 시안 `CPU캐릭터-시안.html` 시안 1 (검토요청 폴더) | 몸 넓이 = CPU, 기분(졸기·땀·김)이 한눈에 읽힌다 | **확정안**. 크기 공식, 색, 얼굴, 움직임을 그대로 옮겼다 |
| [하리보 스타일 반투명 젤리곰 재질](https://80.lv/articles/how-to-create-a-haribo-style-translucent-jelly-bear-candy-material/) | 몸 안에서 빛이 퍼지는 젤리 느낌 | 5차 3D 시안에서 썼다. 앱에는 안 넣음(3D 필요) |
| [JellyBlob (three.js)](https://discourse.threejs.org/t/jellyblob-wobbly-jellies-and-slime-trail-combat-in-three-js/94682) | 투과 + 코팅 광택 + 표면 출렁임 | 5차 시안. 무겁고 macOS 15가 필요해서 피함 |
| [투명 유리·플라스틱 (Codrops)](https://tympanus.net/codrops/2021/10/27/creating-the-effect-of-transparent-glass-and-plastic-in-three-js/) | 투명 재질 값 잡는 법 | 투명 물체가 많으면 무거워진다는 점 → 2D 선택 근거 |
| [RealityKit PhysicallyBasedMaterial](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial) | 앱에서 쓸 수 있는 3D 재질 | 나중에 3D로 갈 때의 후보 |

- 사용자 반응 기록: 2차 "더 구려졌다", 3차 "2D 그림판 같다", 4차 "젤리빈처럼 실제 렌더링", 5차 3D 뒤 "그냥 맨 처음 시안대로".
- 피할 것: 바닥이 몸을 가리는 구성은 두더지처럼 보인다는 의견이 있었다(사용자가 그래도 처음 시안 그대로를 골랐다).
