import SwiftUI
import AppKit
import ServiceManagement
import BackstageCore

let relFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.unitsStyle = .short
    return f
}()

let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "M/d(E) HH:mm"
    return f
}()

func relative(_ date: Date) -> String { relFormatter.localizedString(for: date, relativeTo: Date()) }

/// 상태 표시. 색만으로 가르지 않고 모양을 다르게 하고, 올리면 뜻이 나온다.
struct StatusMark: View {
    let job: Job
    let home: String

    var look: (symbol: String, color: Color, help: String) {
        if job.failed { return ("exclamationmark.triangle.fill", .red, "마지막 실행이 실패로 끝남") }
        switch job.status {
        case .running: return ("circle.fill", .green, "지금 실행 중")
        case .notLoaded: return ("circle.dotted", .secondary, "launchd 에 올라가 있지 않음")
        case .disabled: return ("circle.slash", .secondary, "꺼 둔 작업")
        case .neverRan: return ("circle.dashed", .secondary, "등록됐지만 아직 돈 적 없음")
        case .interrupted: return ("stop.circle", .secondary, "로그아웃·재시동 때 종료 신호로 끝남(고장 아님)")
        default:
            if !job.riskyPaths(home: home).isEmpty {
                return ("exclamationmark.circle", .orange, "보호 폴더의 파일을 써서 백그라운드 실행이 막힐 수 있음")
            }
            return ("circle", .blue, "대기 중")
        }
    }

    var body: some View {
        let l = look
        Image(systemName: l.symbol).foregroundStyle(l.color).font(.system(size: 11))
            .frame(width: 14)
            .help(l.help)
            .accessibilityLabel(l.help)
    }
}

/// 출처 앱의 이름과 아이콘. 찾는 일은 한 번만 하고 기억한다.
@MainActor
final class OwnerLookup {
    static let shared = OwnerLookup()
    var demo = false
    private var cache: [Owner: (String, NSImage?)] = [:]

    func info(_ owner: Owner, missing: Bool) -> (name: String, icon: NSImage?) {
        if let hit = cache[owner] { return hit }
        let result: (String, NSImage?)
        switch owner {
        case .selfMade: result = ("직접 만든 것으로 보임", nil)
        case .unknown: result = ("출처 모름", nil)
        case .app(let path):
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if demo || missing { result = (missing ? "\(name) (지워진 앱)" : name, nil) }
            else { result = (name, NSWorkspace.shared.icon(forFile: path)) }
        case .bundleID(let id):
            if !demo, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                result = ((url.lastPathComponent as NSString).deletingPathExtension, NSWorkspace.shared.icon(forFile: url.path))
            } else { result = (id, nil) }
        }
        cache[owner] = result
        return result
    }
}

struct OwnerLabel: View {
    let job: Job
    var body: some View {
        let info = OwnerLookup.shared.info(job.owner, missing: job.ownerMissing)
        HStack(spacing: 4) {
            if let icon = info.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
            Text(info.name).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// "마지막 실행" 한 줄. 기록부에 있으면 그 시각, 없으면 로그가 마지막으로 바뀐 때.
func lastRunText(_ summary: RunSummary?, logChanged: Date?) -> (text: String, help: String)? {
    if let s = summary, let at = s.lastAt {
        // 오래 살펴보지 못한 사이에 돈 것이면 정확한 시각을 모른다
        let vague = s.lastSince.map { at.timeIntervalSince($0) > 900 } ?? false
        let result = s.lastExit.map { $0 == 0 ? "정상" : exitDescription($0) } ?? "결과 모름"
        return ((vague ? "늦어도 " : "") + relative(at) + " · " + result,
                vague ? "Backstage 가 살펴보지 못한 사이에 돌았습니다. 끝난 것을 알아챈 시각입니다."
                      : "Backstage 가 실행이 끝난 것을 알아챈 시각입니다.")
    }
    if let d = logChanged {
        return ("로그 변경 " + relative(d), "실행 기록이 아직 없어, 로그 파일이 마지막으로 바뀐 때를 보여 줍니다.")
    }
    return nil
}

/// 최근 실행 결과를 점으로. 오래된 것이 왼쪽.
struct RunDots: View {
    let recent: [Int?]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, code in
                if let code {
                    if code == 0 { Circle().fill(.green).frame(width: 7, height: 7) }
                    else if Job.isInterrupt(code) { Circle().stroke(.secondary).frame(width: 7, height: 7) }
                    else { Rectangle().fill(.red).frame(width: 7, height: 7) }
                } else {
                    Circle().fill(.quaternary).frame(width: 7, height: 7)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 로그인할 때 자동으로 켜기 (macOS 로그인 항목, SMAppService). 묻고 나서 등록한다.

@MainActor
final class LoginItem: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?
    @Published var shouldAsk: Bool

    static let askedKey = "askedLoginItem"

    init(demo: Bool) {
        // dmg 안에서 바로 실행한 경우 등록하면 로그인 항목이 dmg 경로를 가리키므로, 응용 프로그램 폴더에 있을 때만 묻는다
        let path = Bundle.main.bundlePath
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        let d = UserDefaults.standard
        // 1.0 은 묻지 않고 등록했다. 그때 등록된 사용자에게는 다시 묻지 않는다.
        let asked = d.bool(forKey: LoginItem.askedKey) || d.bool(forKey: "didRegisterLoginItem")
        shouldAsk = installed && !demo && !asked && SMAppService.mainApp.status != .enabled
    }

    func set(_ want: Bool) {
        do {
            if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        enabled = SMAppService.mainApp.status == .enabled
        answered()
    }

    func answered() {
        UserDefaults.standard.set(true, forKey: LoginItem.askedKey)
        shouldAsk = false
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
