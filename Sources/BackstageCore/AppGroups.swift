import Foundation

/// 같은 앱에서 나온 프로세스를 하나로 합친 것. 브라우저처럼 도우미가 여럿인 앱을 한 캐릭터로 보여 주려고 쓴다.
public struct AppGroup: Identifiable, Hashable, Sendable {
    /// `.app` 번들 경로, 앱이 아니면 `실행 파일 경로#PID`
    public let id: String
    public let name: String
    /// 앱이면 번들 경로. 아이콘과 정상 종료 요청에 쓴다.
    public let appPath: String?
    public let procs: [Proc]

    public var pids: [Int] { procs.map(\.id) }
    /// 코어 하나가 100%. 여러 코어를 쓰면 100을 넘는다.
    public var cpu: Double { procs.reduce(0) { $0 + $1.cpu } }
    public var mem: Double { procs.reduce(0) { $0 + $1.mem } }
    /// 가장 오래 돈 프로세스의 실행 시간(초). 보통 앱 본체다.
    public var elapsedSeconds: Int { procs.compactMap { parseElapsed($0.elapsed) }.max() ?? 0 }
    public var mood: CPUMood { CPUMood(cpu: cpu) }

    public init(id: String, name: String, appPath: String?, procs: [Proc]) {
        self.id = id; self.name = name; self.appPath = appPath; self.procs = procs
    }
}

/// 경로에서 가장 바깥 `.app` 번들. 도우미는 `X.app/Contents/Frameworks/…/Helper.app/…`에 있어서 바깥 것을 고른다.
public func outermostAppBundle(_ path: String) -> String? {
    guard path.hasPrefix("/"), let r = path.range(of: ".app/") else { return nil }
    return String(path[..<path.index(r.lowerBound, offsetBy: 4)])
}

/// 프로세스를 앱 단위로 합치고 CPU가 큰 순으로 줄 세운다.
/// 앱이 아닌 실행 파일(`node`, CLI 등)은 합치지 않는다. 서로 다른 일을 하는 것일 수 있어서, 하나를 끄려다 전부 끄지 않게.
public func groupByApp(_ procs: [Proc]) -> [AppGroup] {
    var order: [String] = []
    var buckets: [String: (app: String?, procs: [Proc])] = [:]
    for p in procs {
        let app = outermostAppBundle(p.path)
        let key = app ?? "\(p.path)#\(p.id)"
        if buckets[key] == nil { order.append(key); buckets[key] = (app, []) }
        buckets[key]!.procs.append(p)
    }
    return order.map { key in
        let b = buckets[key]!
        let name = b.app.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            ?? (b.procs[0].path as NSString).lastPathComponent
        return AppGroup(id: key, name: name, appPath: b.app, procs: b.procs)
    }
    .sorted { $0.cpu == $1.cpu ? $0.mem > $1.mem : $0.cpu > $1.cpu }
}

/// `ps`의 etime(`[[dd-]hh:]mm:ss`)을 초로.
public func parseElapsed(_ s: String) -> Int? {
    var days = 0
    var rest = Substring(s)
    if let dash = rest.firstIndex(of: "-") {
        guard let d = Int(rest[..<dash]) else { return nil }
        days = d
        rest = rest[rest.index(after: dash)...]
    }
    let parts = rest.split(separator: ":").map { Int($0) }
    guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
    let n = parts.compactMap { $0 }
    let (h, m, sec) = n.count == 3 ? (n[0], n[1], n[2]) : (0, n[0], n[1])
    return ((days * 24 + h) * 60 + m) * 60 + sec
}

/// "3시간 12분"처럼 읽기 쉬운 실행 시간.
public func describeElapsed(_ seconds: Int) -> String {
    let d = seconds / 86400, h = seconds % 86400 / 3600, m = seconds % 3600 / 60
    if d > 0 { return h > 0 ? "\(d)일 \(h)시간" : "\(d)일" }
    if h > 0 { return m > 0 ? "\(h)시간 \(m)분" : "\(h)시간" }
    if m > 0 { return "\(m)분" }
    return "1분 안"
}

/// CPU를 얼마나 쓰는지에 따른 캐릭터 기분.
public enum CPUMood: String, Sendable {
    case sleep, happy, busy, sweat, boil

    public init(cpu: Double) {
        switch cpu {
        case ..<1: self = .sleep
        case ..<15: self = .happy
        case ..<50: self = .busy
        case ..<100: self = .sweat
        default: self = .boil
        }
    }

    public var text: String {
        switch self {
        case .sleep: "꾸벅꾸벅 자는 중"
        case .happy: "한가해요"
        case .busy: "열심히 일하는 중"
        case .sweat: "땀 뻘뻘, CPU 많이 씀"
        case .boil: "과열! 코어 여러 개를 먹는 중"
        }
    }
}

/// 종료 버튼을 줄지. macOS 시스템 위치의 프로그램과 Backstage 자신은 끄지 않는다.
public func canQuit(_ g: AppGroup, selfPID: Int, selfBundle: String?) -> Bool {
    if g.pids.contains(selfPID) { return false }
    if let selfBundle, g.appPath == selfBundle { return false }
    let systemRoots = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]
    return !g.procs.contains { p in systemRoots.contains { p.path.hasPrefix($0) } }
}

/// ps가 본 프로세스가 지금 그 PID의 프로세스와 같은지. PID는 재사용되니 신호를 보내기 전에 확인한다.
/// ps는 실행할 때 쓴 경로(`/tmp/…`, `/opt/homebrew/bin/node`)를, 커널은 링크를 푼 실제 경로(`/private/tmp/…`, `…/Cellar/…`)를
/// 주므로 전체 경로가 아니라 실행 파일 이름으로 비교한다. ps가 이름만 준 경우(`claude` 등)도 같은 방식으로 맞는다.
public func sameProgram(psPath: String, livePath: String) -> Bool {
    (livePath as NSString).lastPathComponent == (psPath as NSString).lastPathComponent
}
