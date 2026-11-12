<p align="center"><img src="docs/images/icon-1024.png" width="120" alt="Backstage"></p>

<h1 align="center">Backstage</h1>

<p align="center">맥의 무대 뒤를 보여 주는 메뉴바 앱입니다.<br>
예약·상주 작업이 언제 도는지, 지난번에 잘 돌았는지 알려 주고,<br>
지금 CPU를 쓰는 프로그램은 말랑한 캐릭터로 보여 줍니다.</p>

<p align="center"><a href="https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg"><b>⬇ Mac용 내려받기</b></a><br>
<sub>Apple 실리콘·인텔 · 서명·공증 완료 · macOS 14 이상 · <a href="https://github.com/ESeungJun/backstage/releases">모든 릴리스</a></sub></p>

<p align="center"><a href="README.md">English</a> · <b>한국어</b></p>

<p align="center"><img src="docs/images/procs.png" width="100%" alt="실행 중인 프로그램: CPU를 쓰는 만큼 커지는 캐릭터들과, 가장 바쁜 앱의 상세 정보와 종료 버튼"></p>

---

## 실행 중인 프로그램

내 계정으로 도는 앱을 하나씩 캐릭터로 세워 둡니다. CPU를 많이 쓸수록 커집니다.

- 거의 안 쓰면 자고, 50%를 넘으면 땀을 흘리고, 100%를 넘으면 머리에서 김이 납니다. 코어 하나를 다 쓰면 100%입니다.
- 머리 위에는 그 앱의 아이콘을 모자처럼 씁니다.
- 브라우저처럼 도우미 프로세스가 여럿인 앱은 하나로 합칩니다. macOS 시스템 프로세스는 뺍니다.
- 캐릭터를 고르면 CPU, 메모리, 합친 프로세스 수, 실행 시간이 나옵니다. `표`로 바꾸면 프로세스를 하나씩 볼 수 있습니다.
- 무대에 다 못 올라간 앱은 오른쪽 위 `그 밖에 N개` 메뉴에 있습니다.

**프로그램 끄기.** `종료…`를 누르고 확인하면 앱에는 정상 종료를 요청합니다. 저장 안 한 문서가 있으면 앱이 물어봅니다.
앱이 아닌 프로그램에는 `SIGTERM`을 보냅니다. 5초가 지나도 안 꺼지면 강제 종료를 고를 수 있습니다.
macOS 시스템 프로그램과 Backstage 자신에는 종료 버튼이 없습니다.

캐릭터의 움직임은 Core Animation이 그리기 때문에, 이 화면을 켜 둬도 Backstage는 CPU를 거의 쓰지 않습니다(창을 열어 둔 채 평균 0.6%).
손쉬운 사용의 '동작 줄이기'를 켜면 캐릭터가 멈춥니다.

## 예약·상주 작업

macOS는 launchd로 많은 작업을 정해진 시간에 돌리거나 백그라운드에 계속 켜 둡니다.
`launchctl list`로 보면 라벨과 숫자만 잔뜩 나오는데, Backstage는 같은 정보를 읽어서 알아보기 쉽게 보여 줍니다.

<p align="center"><img src="docs/images/hero.png" width="100%" alt="전체 보기: 예약·상주 작업 표와 실패한 작업의 상세 정보"></p>

- **일정**: `매일 19:07`, `매주 월요일 09:10`, `30분마다`처럼 문장으로 보여 주고 다음 실행 시각도 적습니다.
- **상태**: `실행 중`, `정상 · 686회 실행`, `아직 돈 적 없음`, `꺼 둠`, `중단됨`(로그아웃·재시동 때의 종료 신호), `실행 불가(126)`, `명령을 찾지 못함(127)` 등으로 나눕니다. 등록만 되고 한 번도 안 돈 작업을 "정상"이라고 하지 않습니다.
- **실행 기록**: launchd는 마지막 실행 시각을 알려 주지 않습니다. Backstage가 켜져 있는 동안 실행 횟수가 느는 것을 보고 직접 기록해서, 마지막 실행과 최근 14회 결과, 성공률을 보여 줍니다.
- **누가 심었는지**: 항목마다 출처 앱의 이름과 아이콘을 붙입니다. 앱을 지우고 항목만 남았으면 `지워진 앱`으로 나옵니다.
- **앱이 심은 항목**: `LaunchAgents` 폴더에 파일이 없는 것(앱 번들 안의 에이전트, 실행 중에 등록한 서비스)도 찾아냅니다.
- **새로 들어온 항목**: 처음 본 목록을 기준으로, 그 뒤에 생긴 항목에는 7일 동안 `새 항목` 표시를 붙입니다. 시스템 알림도 켤 수 있습니다(기본은 꺼짐).
- **권한 함정**: 데스크탑·문서·다운로드·iCloud Drive·외장 볼륨의 파일을 쓰는 작업은 백그라운드에서 막힐 수 있어서 주황색으로 표시하고 고치는 방법을 알려 줍니다.
- **상세와 로그**: 전체 명령, 작업 폴더, 설정 파일, 로그 마지막 부분을 보여 주고, 직접 확인할 `launchctl print …` 명령을 복사할 수 있습니다.

작업은 읽기만 합니다. 켜거나, 끄거나, 고치거나, 지우지 않습니다.

## 메뉴바

<p align="center"><img src="docs/images/popover.png" width="420" alt="메뉴바 요약: 살펴볼 것, 새로 들어온 항목, CPU 제일 많이 쓰는 앱, 다음 큐"></p>

- 메뉴바의 캐릭터 아이콘을 누르면 요약이 내려옵니다. 살펴볼 것, 새로 들어온 항목, CPU를 제일 많이 쓰는 앱, 다음 실행, 지금 돌고 있는 작업이 나옵니다.
- 내 에이전트가 실패했을 때만 아이콘이 경고 표시와 개수로 바뀝니다. 남이 심은 데몬의 실패나 로그아웃 때의 종료 신호는 세지 않습니다.
- 요약이나 창을 열면 새로 읽고, 열려 있는 동안은 30초마다, 닫혀 있으면 5분마다 읽습니다. ⌘R로 바로 새로고칠 수 있습니다.
- 처음 열 때 로그인 시 실행할지 한 번 묻습니다. `⋯` 메뉴에서 언제든 바꿀 수 있습니다.
- Dock 아이콘은 없습니다.

## 설치

[`Backstage-macOS.dmg`](https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg)를 내려받아 열고, `Backstage.app`을 응용 프로그램 폴더로 옮기면 됩니다.
파일 하나로 Apple 실리콘과 인텔 맥 모두에서 돌아갑니다. Developer ID로 서명하고 Apple 공증을 받아서 경고 없이 열립니다.

macOS 14 이상이 필요하고, 따로 허락할 권한은 없습니다. 화면은 한국어입니다.
launchd를 읽는 앱이라 macOS 전용입니다.

Backstage가 쓰는 파일은 자기 기록(`~/Library/Application Support/Backstage/`의 실행 기록·기준선)과 설정뿐입니다.

## 만든 방법

외부 의존성 없는 Swift Package이고, SwiftUI와 AppKit으로 만들었습니다.

- `BackstageCore`: plist·`launchctl`·`ps` 출력 해석, 일정 문장, 상태 판정, 실행 기록, 프로세스를 앱 단위로 묶기. Foundation만 씁니다.
- `Backstage`: 메뉴바(`NSStatusItem`, `NSPopover`), 전체 보기 창, 캐릭터 무대(`ProcsView`), 프로그램 끄기(`Quitter`), 로그인 시 실행(`SMAppService`).
- 상태는 도메인마다 `launchctl print`를 한 번 부르고, 필요한 서비스만 따로 묻습니다. 같은 PID로 계속 도는 서비스는 다시 묻지 않습니다.

Claude Code와 함께 만들었습니다.

## 개발

```bash
swift build                    # 디버그 빌드
swift test                     # 테스트 (XCTest 가 없으면 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
./build.sh                     # build/Backstage.app (유니버설, ad-hoc 서명)
./build.sh --install           # 빌드해서 ~/Applications 에 넣고 실행
.build/debug/Backstage --demo --window --procs   # 예시 데이터로 실행 중인 프로그램 탭 열기
.build/debug/Backstage --probe                   # 화면 없이 수집 한 번의 프로세스 수·시간
.build/debug/Backstage --snapshot <폴더>          # 예시 화면을 PNG 로 저장 (README 그림, --dark 면 다크 모드)
```

개발 빌드는 기록을 `Backstage-dev` 폴더에 따로 둬서 설치본과 섞이지 않습니다.

<details>
<summary>프로젝트 구성과 릴리스</summary>

| 경로 | 역할 |
|---|---|
| `Sources/BackstageCore` | 해석, 일정 문장, 상태 판정, 수집, 실행 기록, 앱 단위 묶기 |
| `Sources/Backstage` | 메뉴바, 요약 패널, 전체 보기 창, 캐릭터 무대, 프로그램 끄기 |
| `Tests/BackstageCoreTests` | 지어낸 라벨로 만든 `launchctl` 출력 고정 자료와 테스트 |
| `build.sh` | arm64·x86_64로 빌드해 합치고, 아이콘과 Info.plist를 만들고, 서명 |
| `tools/make_icon.swift` | 앱 아이콘(`docs/images/icon-1024.png`)을 그림 |
| `docs/` | 설계서, 결정 기록, QA 체크, 디자인 시스템 |
| `VERSION` | 앱 버전. 릴리스 태그와 같아야 함(`v2.0.0`) |

push와 PR마다 `.github/workflows/ci.yml`이 `swift build`와 `swift test`를 돌립니다.
`v*` 태그를 push하면 GitHub Actions가 유니버설 앱을 빌드해 Developer ID로 서명하고, 앱과 DMG를 공증받아 `Backstage-macOS.dmg`를 릴리스로 올립니다.
필요한 Secrets: `MAC_CERT_P12`, `MAC_CERT_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`.

</details>
