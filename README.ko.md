<p align="center"><img src="docs/images/icon-1024.png" width="120" alt="Backstage"></p>

<h1 align="center">Backstage</h1>

<p align="center">맥의 무대 뒤에서 돌고 있는 것들을 한눈에 보여주는 메뉴바 앱입니다.<br>
예약 작업, 항상 켜져 있는 에이전트, 백그라운드 프로그램이 다음에 언제 도는지, 지난번에 잘 돌았는지 알려 줍니다.</p>

<p align="center"><a href="https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg"><b>⬇ Mac용 내려받기</b></a><br>
<sub>Apple 실리콘·인텔 모두 · 서명·공증 완료 · macOS 14 이상 · <a href="https://github.com/ESeungJun/backstage/releases">모든 릴리스</a></sub></p>

<p align="center"><a href="README.md">English</a> · <b>한국어</b></p>

<p align="center"><img src="docs/images/hero.png" width="100%" alt="Backstage 전체 보기: 예약·상주 작업 표와 실패한 작업의 상세 정보"></p>

---

Backstage는 백그라운드 작업을 확인하는 용도의 작은 도구입니다.
macOS는 launchd로 많은 작업을 시간 맞춰 돌리거나 백그라운드에 계속 켜 두는데,
`launchctl list`로는 라벨과 숫자만 잔뜩 나옵니다.
Backstage는 같은 정보를 읽어서 무엇이 언제 도는지, 지금 무엇이 돌고 있는지, 무엇이 실패했는지를 알아보기 쉽게 보여 줍니다.

## 보여주는 것

- **예약 작업** — 일정을 문장으로 풀어 보여 줍니다(`매일 19:07`, `매주 월요일 09:10`, `30분마다`). 다음 실행 시각도 나옵니다.
- **상주 에이전트** — launchd가 계속 켜 두는 작업이 지금 돌고 있는지(PID 포함) 보여 줍니다.
- **앱이 심은 항목** — `LaunchAgents`·`LaunchDaemons` 폴더에 파일이 없는 것도 보여 줍니다.
  앱 번들 안에 든 에이전트(`SMAppService`), 프로그램이 실행 중에 직접 등록한 서비스가 여기에 해당합니다.
  `com.apple.*` 과 `/System` 아래의 macOS 기본 서비스, 평소처럼 실행한 앱은 뺍니다.
- **누가 심었는지** — 항목마다 출처 앱을 찾아 이름과 아이콘으로 보여 줍니다. 홈 폴더의 스크립트를 돌리는 내 에이전트는 `직접 만든 것으로 보임`,
  앱이 지워지고 항목만 남았으면 `지워진 앱`으로 나옵니다.
- **상태를 사실대로** — `실행 중`, `정상 · 686회 실행`, `아직 돈 적 없음`, `꺼 둠`, `중단됨`(로그아웃·재시동 때의 종료 신호),
  `실행 불가(126) · 파일 접근 권한 문제일 수 있음`, `명령을 찾지 못함(127)` 등으로 나눕니다. 등록만 되고 한 번도 안 돈 작업을 "정상"이라고 하지 않습니다.
- **실행 기록** — launchd는 마지막 실행 시각을 알려 주지 않습니다. Backstage가 켜져 있는 동안 실행 횟수가 느는 것을 지켜보고
  직접 본 실행(끝난 것을 알아챈 시각, 종료 코드)을 적어 두었다가 마지막 실행과 최근 14회의 성공·실패, 성공률을 보여 줍니다.
  기록이 아직 없으면 로그 파일이 마지막으로 바뀐 때를 대신 보여 줍니다.
- **새로 들어온 항목** — 처음 켰을 때의 목록을 기준선으로 삼고, 그 뒤에 생긴 항목에 7일 동안 `새 항목` 표시를 붙입니다. 원하면 시스템 알림도 받을 수 있습니다(기본은 꺼짐).
- **읽을 수 없는 설정 파일** — 관리자만 읽을 수 있는 데몬 설정 파일도 목록에서 빼지 않고 자물쇠 표시와 함께 보여 줍니다. 상태와 실행 파일은 `launchctl`에서 채웁니다.
- **권한 함정** — 데스크탑·문서·다운로드·iCloud Drive·외장 볼륨의 파일을 쓰는 작업은 주황색으로 표시합니다.
  백그라운드에서 왜 실패할 수 있는지, 어떻게 고치는지(폴더를 `~/Projects` 같은 곳으로 옮기기)도 함께 알려 줍니다.
- **상세 정보와 로그** — 작업을 고르면 전체 명령, 작업 폴더, 설정 파일, 로그 마지막 부분이 나옵니다.
  설정 파일을 Finder에서 보거나, 로그를 열거나, 터미널에서 직접 확인할 명령(`launchctl print …`)을 복사할 수 있습니다.
- **검색과 필터** — 이름·경로·앱 이름으로 찾고, `살펴볼 것`·`예약`·`상주`·`새로 들어옴`·`꺼짐`과 출처별로 거릅니다.
- **실행 중인 프로그램** — 두 번째 탭에서 내 계정으로 도는 앱을 말랑한 캐릭터로 보여 줍니다. CPU를 많이 쓸수록 뚱뚱해져요.
  거의 안 쓰면 졸고, 50%를 넘으면 땀을 흘리고, 100%를 넘으면 김이 납니다(코어 하나가 100%). 도우미 프로세스는 앱 하나로 합치고, macOS 시스템 프로세스는 뺍니다.
  캐릭터를 고르면 CPU·메모리·실행 시간이 보이고, `표`로 바꾸면 프로세스 하나하나를 볼 수 있습니다.
- **프로그램 끄기** — `종료…`를 누르고 확인하면, 앱에는 정상 종료를 요청하고(저장할 게 있으면 앱이 물어봅니다) 그 밖의 프로그램에는 `SIGTERM`을 보냅니다.
  5초가 지나도 안 꺼지면 강제 종료를 고를 수 있습니다. macOS 시스템 프로그램과 Backstage 자신에는 종료 버튼이 없습니다.
  움직임은 Core Animation이 그려서 CPU를 보는 화면이 CPU를 먹지 않고, 손쉬운 사용의 '동작 줄이기'를 켜면 멈춥니다.

## 메뉴바에 두고 쓰는 앱

- **클릭 한 번** — 메뉴바 아이콘을 누르면 작은 요약이 내려옵니다: 살펴볼 것, 새로 들어온 항목, 다음 큐, 지금 무대 위.
  `전체 보기`를 누르면 모든 작업이 든 창이 열립니다. Dock 아이콘은 없습니다.
- **볼 일이 있을 때만 알려 줌** — 내 에이전트가 실패로 끝났을 때만 메뉴바 아이콘이 경고 표시와 개수로 바뀝니다.
  남이 심은 데몬의 실패나 로그아웃 때의 종료 신호는 세지 않습니다. `확인함`을 누르면 그 실패는 빠지고, 다시 돌아 또 실패하면 다시 알려 줍니다.
- **조용히 갱신** — 요약이나 창을 열 때 새로 읽고, 열려 있는 동안은 30초마다, 닫혀 있을 때는 5분마다 읽습니다(⌘R로 바로 새로고침).
- **로그인 시 실행** — 처음 열 때 한 번 물어봅니다. 요약 아래 `⋯` 메뉴에서 언제든 켜고 끌 수 있습니다.
- **작업은 읽기만** — 작업을 켜거나, 끄거나, 고치거나, 지우지 않습니다. plist, `launchctl print`, `ps`만 읽습니다.
  끄는 것은 '실행 중인 프로그램' 탭에서 직접 고르고 확인한 프로그램 하나뿐입니다.
  쓰는 것은 자기 기록(`~/Library/Application Support/Backstage/`의 실행 기록·기준선)과 설정뿐입니다.

<p align="center"><img src="docs/images/procs.png" width="100%" alt="실행 중인 프로그램: CPU만큼 뚱뚱한 젤리 캐릭터들과, 가장 바쁜 앱의 상세 정보와 종료 버튼"></p>

<p align="center"><img src="docs/images/popover.png" width="420" alt="메뉴바 요약: 살펴볼 것, CPU 제일 많이 쓰는 앱, 새로 들어온 항목, 다음 큐, 지금 무대 위"></p>

## 설치

[`Backstage-macOS.dmg`](https://github.com/ESeungJun/backstage/releases/latest/download/Backstage-macOS.dmg)를 내려받아 열고,
`Backstage.app`을 응용 프로그램 폴더로 끌어다 놓으면 됩니다.
파일 하나로 Apple 실리콘과 인텔 맥 모두에서 돌아갑니다.
Developer ID로 서명하고 Apple 공증을 받았기 때문에 경고 없이 열립니다.

macOS 14 이상이 필요하고, 따로 허락할 권한은 없습니다.
실행하면 메뉴바에 막 모양 아이콘이 생깁니다(Dock 아이콘은 없습니다).

Backstage는 macOS 전용입니다. macOS가 백그라운드 작업을 돌리는 방식인 launchd를 읽는 앱이기 때문입니다.

## 만든 방법

- **SwiftUI + AppKit**, 외부 의존성 없는 Swift Package 입니다.
  `BackstageCore`(모델·해석·수집, Foundation 만 사용)와 `Backstage`(화면·메뉴바)로 나뉩니다.
  메뉴바 아이콘은 `NSStatusItem`과 `NSPopover`, 로그인 시 실행은 `SMAppService`를 씁니다.
- 일정은 `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`의 plist에서 읽습니다.
  상태는 `launchctl print gui/<uid>`·`launchctl print system`(도메인마다 한 번)과 서비스별 `launchctl print`, 프로세스는 `ps`에서 가져옵니다.
  같은 PID로 계속 돌고 있는 서비스는 다시 묻지 않습니다.

Claude Code와 함께 만들었습니다.

## 개발

```bash
swift build              # 디버그 빌드
swift test               # 파서·모델 테스트 (XCTest 가 없으면 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
./build.sh               # build/Backstage.app (유니버설, ad-hoc 서명)
./build.sh --install     # 빌드한 뒤 ~/Applications 에 복사하고 실행
open build/Backstage.app --args --demo --window   # 예시 데이터를 전체 보기 창으로 (--procs 를 더하면 실행 중인 프로그램 탭)
.build/debug/Backstage --probe                    # 화면 없이 수집 한 번의 프로세스 수·시간을 잰다
.build/debug/Backstage --snapshot <폴더>           # 예시 화면을 화면에 띄우지 않고 PNG 로 저장 (README 그림, --dark 면 다크 모드)
```

<details>
<summary>프로젝트 구성과 릴리스</summary>

| 경로 | 역할 |
|---|---|
| `Sources/BackstageCore` | plist·`launchctl` 출력 해석, 일정 문장, 상태 판정, 수집, 실행 기록부, 프로세스를 앱 단위로 묶기 |
| `Sources/Backstage` | 메뉴바 아이콘, 요약 패널, 전체 보기 창, CPU 캐릭터(`ProcsView`)와 프로그램 끄기(`Quitter`) |
| `Tests/BackstageCoreTests` | 지어낸 라벨로 만든 `launchctl` 출력 고정 자료와 테스트 |
| `build.sh` | arm64·x86_64로 `swift build` 해 합치고, 아이콘과 Info.plist를 만들고, 서명 |
| `tools/make_icon.swift` | 앱 아이콘(`docs/images/icon-1024.png`)을 그림 |
| `VERSION` | 앱 버전. 릴리스 태그와 같아야 함(`v1.1.0`) |

push·PR 마다 `.github/workflows/ci.yml` 이 `swift build`·`swift test` 를 돌립니다.
`v*` 태그를 push하면 GitHub Actions가 유니버설 앱을 빌드하고, 하드닝 런타임으로 Developer ID 서명을 합니다.
그다음 앱과 DMG를 각각 공증받아 티켓을 붙이고, `Backstage-macOS.dmg`를 릴리스로 올립니다.
필요한 Secrets: `MAC_CERT_P12`, `MAC_CERT_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`.

</details>
