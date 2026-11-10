import Foundation

/// `launchctl print gui/<uid>` · `launchctl print system` 의 서비스 한 줄.
public struct ServiceRow: Hashable, Sendable {
    public let label: String
    public let pid: Int?        // 돌고 있지 않으면 nil
    public let lastExit: Int?   // "-", "(pe)" 같은 표시는 nil

    public init(label: String, pid: Int?, lastExit: Int?) {
        self.label = label; self.pid = pid; self.lastExit = lastExit
    }
}

public struct DomainSnapshot: Sendable {
    public var services: [String: ServiceRow] = [:]
    public var disabled: Set<String> = []
    public init() {}
}

/// 도메인 전체 출력에서 `services = { … }` 와 `disabled services = { … }` 블록만 읽는다.
public func parseDomainPrint(_ text: String) -> DomainSnapshot {
    var snap = DomainSnapshot()
    var block = ""
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if line == "\tservices = {" { block = "services"; continue }
        if line == "\tdisabled services = {" { block = "disabled"; continue }
        if line.hasPrefix("\t}") || (line.hasPrefix("\t") && !line.hasPrefix("\t\t")) { block = ""; continue }
        guard line.hasPrefix("\t\t") else { continue }
        if block == "services" {
            // "   32487      - \tcom.example.agent" (PID, 마지막 종료 코드, 라벨)
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard cols.count >= 3, let pid = Int(cols[0]) else { continue }
            let label = cols[2...].joined(separator: " ")
            snap.services[label] = ServiceRow(label: label, pid: pid > 0 ? pid : nil, lastExit: Int(cols[1]))
        } else if block == "disabled" {
            // "\"com.example.agent\" => disabled"
            let parts = line.components(separatedBy: " => ")
            guard parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces) == "disabled" else { continue }
            snap.disabled.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
        }
    }
    return snap
}

/// `launchctl print <도메인>/<라벨>` 에서 읽는 것.
public struct ServiceDetail: Hashable, Sendable {
    public var plistPath: String?        // 실제 파일 경로일 때만
    public var submittedBy: String?      // "(submitted by smd[123])" → "smd"
    public var type: String?
    public var managedBy: String?
    public var program: String?
    public var arguments: [String] = []
    public var workingDir: String?
    public var stdoutPath: String?
    public var stderrPath: String?
    public var bundleID: String?
    public var parentBundleID: String?
    public var programIdentifier: String?
    public var runs: Int?
    public var pid: Int?
    public var lastExit: Int?
    public var neverExited = false
    public init() {}

    /// 실행 명령. arguments 블록이 없으면 program 한 단어.
    public var commandLine: [String] {
        if !arguments.isEmpty { return arguments }
        if let program { return [program] }
        if let programIdentifier { return [programIdentifier] }
        return []
    }
}

/// 서비스 하나의 출력을 읽는다. 서비스를 찾지 못한 출력이면 nil.
public func parseServicePrint(_ text: String) -> ServiceDetail? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let first = lines.first, first.hasSuffix(" = {"), !first.hasPrefix("\t") else { return nil }
    var d = ServiceDetail()
    var inArguments = false
    for line in lines.dropFirst() {
        if inArguments {
            if line.hasPrefix("\t\t") { d.arguments.append(String(line.dropFirst(2))) } else { inArguments = false }
            if inArguments { continue }
        }
        // 최상위 키만 본다(탭 하나). 중첩 블록의 같은 이름 키와 섞이지 않게.
        guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
        let body = line.dropFirst()
        if body == "arguments = {" { inArguments = true; continue }
        guard let r = body.range(of: " = ") else { continue }
        let key = String(body[..<r.lowerBound]), value = String(body[r.upperBound...])
        switch key {
        case "path":
            if value.hasPrefix("/") { d.plistPath = value }
            else if value.hasPrefix("(submitted by ") {
                // "(submitted by smd[123])" · "(submitted by loginwindow)"
                let who = value.dropFirst("(submitted by ".count).prefix { $0 != "[" && $0 != ")" }
                d.submittedBy = String(who)
            }
        case "type": d.type = value
        case "managed_by": d.managedBy = value
        case "program": d.program = value
        case "working directory": d.workingDir = value
        case "stdout path": d.stdoutPath = value
        case "stderr path": d.stderrPath = value
        case "bundle id": d.bundleID = value
        case "parent bundle identifier": d.parentBundleID = value
        case "program identifier":
            // "Contents/Library/LoginItems/Helper.app (mode: 1)" → 앞부분만
            d.programIdentifier = value.components(separatedBy: " (mode:").first
        case "runs": d.runs = Int(value)
        case "pid": d.pid = Int(value)
        case "last exit code":
            if value == "(never exited)" { d.neverExited = true } else { d.lastExit = Int(value) }
        case "last terminating signal":
            // "Terminated: 15" → -15 (launchctl list 와 같은 표기)
            if let n = value.components(separatedBy: ": ").last.flatMap({ Int($0) }) { d.lastExit = -n }
        default: break
        }
    }
    return d
}

/// `ps -axo pid=,uid=,%cpu=,%mem=,etime=,comm=` 에서 내 계정의 프로그램만 고른다.
public func parseProcesses(_ text: String, uid: Int) -> [Proc] {
    var procs: [Proc] = []
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 6, Int(parts[1]) == uid, let pid = Int(parts[0]) else { continue }
        let path = parts[5]
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") { continue }
        procs.append(Proc(id: pid, cpu: Double(parts[2]) ?? 0, mem: Double(parts[3]) ?? 0, elapsed: parts[4], path: path))
    }
    return procs.sorted { $0.cpu == $1.cpu ? $0.mem > $1.mem : $0.cpu > $1.cpu }
}
