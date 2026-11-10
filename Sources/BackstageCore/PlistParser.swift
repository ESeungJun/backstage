import Foundation

/// launchd plist 에서 화면에 쓰는 것만 뽑은 결과.
public struct PlistInfo: Sendable {
    public var label: String?
    public var args: [String] = []
    public var kind: Kind = .manual
    public var schedule = "직접 실행할 때만"
    public var nextRun: Date?
    public var stdoutPath: String?
    public var stderrPath: String?
    public var workingDir: String?
    public var associatedBundleIDs: [String] = []
}

func intDict(_ any: Any) -> [String: Int] {
    var r: [String: Int] = [:]
    (any as? [String: Any])?.forEach { k, v in if let n = v as? Int { r[k] = n } }
    return r
}

/// plist 데이터를 읽는다. plist 가 아니거나 딕셔너리가 아니면 nil.
public func parsePlist(_ data: Data, system: Bool, now: Date, calendar: Calendar = .current) -> PlistInfo? {
    guard let pl = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
    var info = PlistInfo()
    info.label = pl["Label"] as? String
    info.args = pl["ProgramArguments"] as? [String] ?? []
    if let prog = pl["Program"] as? String {
        if info.args.isEmpty { info.args = [prog] } else { info.args[0] = prog }
    }
    let runAtLoad = (pl["RunAtLoad"] as? Bool) == true
    if let cal = pl["StartCalendarInterval"] {
        let entries = (cal as? [Any])?.map(intDict) ?? [intDict(cal)]
        info.kind = .scheduled
        info.schedule = entries.map(describeCalendar).joined(separator: ", ")
        info.nextRun = entries.compactMap { nextCalendarDate($0, after: now, calendar: calendar) }.min()
    } else if let iv = pl["StartInterval"] as? Int {
        info.kind = .scheduled
        info.schedule = describeInterval(iv)
    } else if let ka = pl["KeepAlive"], (ka as? Bool) == true || ka is [String: Any] {
        info.kind = .resident
        info.schedule = (ka as? Bool) == true ? "항상 실행 (죽으면 다시 켬)" : "조건부 상주"
    } else if pl["WatchPaths"] != nil || pl["QueueDirectories"] != nil || pl["MachServices"] != nil || pl["Sockets"] != nil {
        info.kind = .trigger
        info.schedule = "다른 프로그램이 요청할 때"
    } else if runAtLoad {
        info.kind = .atLogin
        info.schedule = system ? "부팅 시 1회" : "로그인 시 1회"
    }
    if info.kind == .scheduled, runAtLoad { info.schedule += system ? " · 부팅 시에도" : " · 로그인 시에도" }
    info.stdoutPath = pl["StandardOutPath"] as? String
    info.stderrPath = pl["StandardErrorPath"] as? String
    info.workingDir = pl["WorkingDirectory"] as? String
    if let one = pl["AssociatedBundleIdentifiers"] as? String { info.associatedBundleIDs = [one] }
    else if let many = pl["AssociatedBundleIdentifiers"] as? [String] { info.associatedBundleIDs = many }
    return info
}

/// 누가 심었는지 추정한다. 확실한 것부터: plist 가 적은 번들 ID → launchctl 이 알려 준 부모 번들 → 경로에 든 .app → 홈 폴더 스크립트.
public func resolveOwner(associated: [String], parentBundleID: String?, paths: [String],
                         source: Source, home: String) -> Owner {
    if let id = associated.first { return .bundleID(id) }
    if let id = parentBundleID, !id.isEmpty { return .bundleID(id) }
    for p in paths {
        if let r = p.range(of: ".app/") ?? (p.hasSuffix(".app") ? p.range(of: ".app", options: .backwards) : nil) {
            return .app(path: String(p[..<r.lowerBound]) + ".app")
        }
    }
    // ~/Library 아래는 앱이 깔아 둔 도우미인 경우가 많아 "직접 만든 것"으로 보지 않는다
    let mine = paths.contains { $0.hasPrefix(home + "/") && !$0.hasPrefix(home + "/Library/") }
    if source == .userAgent, mine { return .selfMade }
    return .unknown
}
