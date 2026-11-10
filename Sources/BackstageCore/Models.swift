import Foundation

public enum Source: String, CaseIterable, Sendable {
    case userAgent = "내 에이전트"
    case globalAgent = "공용 에이전트"
    case daemon = "시스템 데몬"
    /// 세 폴더에 설정 파일이 없는 것. 앱 번들 안 plist(SMAppService)나 프로그램이 직접 등록한 서비스.
    case appEmbedded = "앱이 심은 것"
}

/// launchd 도메인. 에이전트는 gui/<uid>, 데몬은 system.
public enum Domain: String, Sendable {
    case gui, system
}

public enum Kind: String, Sendable {
    case scheduled = "예약"
    case resident = "상주"
    case trigger = "요청 시"
    case atLogin = "로그인 시"
    case manual = "수동"
    case unknown = "알 수 없음"
}

/// 누가 심었는지.
public enum Owner: Hashable, Sendable {
    case app(path: String)       // 경로에 든 .app
    case bundleID(String)        // plist·launchctl 이 알려 준 번들 ID
    case selfMade                // 홈 폴더 아래 스크립트를 돌리는 내 에이전트
    case unknown
}

/// 화면에 쓰는 상태. launchctl 이 알려 준 사실만으로 정한다.
public enum JobStatus: Hashable, Sendable {
    case running(pid: Int)
    case notLoaded               // launchd 에 올라가 있지 않음
    case disabled                // 사용자가 꺼 둠(launchctl disable)
    case neverRan                // 등록됐지만 아직 한 번도 돌지 않음
    case succeeded(runs: Int?)
    case interrupted(code: Int)  // 로그아웃·재시동 때의 SIGTERM/SIGKILL
    case failed(code: Int, runs: Int?)
    case idle                    // 올라가 있지만 실행 기록을 읽지 못함
}

public struct Job: Identifiable, Hashable, Sendable {
    public let id: String            // "<도메인>/<라벨>"
    public let label: String
    public var source: Source
    public let domain: Domain
    public var kind: Kind
    public var schedule: String
    public var nextRun: Date?
    public var args: [String]
    public var stdoutPath: String?
    public var stderrPath: String?
    public var workingDir: String?
    public var plistPath: String?    // 없으면 설정 파일 없이 등록된 서비스
    public var plistReadable = true
    public var origin: String?       // 설정 파일이 없을 때 launchctl 이 알려 준 등록 경위
    public var owner: Owner = .unknown
    public var ownerMissing = false  // 출처 앱이 지워지고 항목만 남음
    public var loaded = false
    public var disabled = false
    public var pid: Int?
    public var lastExit: Int?        // 음수는 신호 번호. nil = 종료 기록 없음/알 수 없음
    public var runs: Int?            // launchd 가 센 실행 횟수. nil = 읽지 못함
    public var neverExited = false   // launchctl 이 "(never exited)" 라고 한 경우

    public init(id: String, label: String, source: Source, domain: Domain, kind: Kind = .unknown,
                schedule: String = "", nextRun: Date? = nil, args: [String] = [],
                stdoutPath: String? = nil, stderrPath: String? = nil, workingDir: String? = nil,
                plistPath: String? = nil) {
        self.id = id; self.label = label; self.source = source; self.domain = domain
        self.kind = kind; self.schedule = schedule; self.nextRun = nextRun; self.args = args
        self.stdoutPath = stdoutPath; self.stderrPath = stderrPath; self.workingDir = workingDir
        self.plistPath = plistPath
    }

    public static func makeID(_ domain: Domain, _ label: String) -> String { "\(domain.rawValue)/\(label)" }

    public var running: Bool { pid != nil }

    /// 로그아웃·재시동 때 받는 종료 신호. 고장이 아니다.
    public static func isInterrupt(_ code: Int) -> Bool { code == -15 || code == -9 }

    public var status: JobStatus {
        if let pid { return .running(pid: pid) }
        if !loaded { return disabled ? .disabled : .notLoaded }
        if runs == 0 || neverExited { return .neverRan }
        guard let e = lastExit else { return .idle }
        if e == 0 {
            // 실행 횟수를 읽지 못했으면 0 이 "성공"인지 "안 돎"인지 알 수 없다
            return runs == nil ? .idle : .succeeded(runs: runs)
        }
        return Job.isInterrupt(e) ? .interrupted(code: e) : .failed(code: e, runs: runs)
    }

    /// 마지막 실행이 실패로 끝났는지. 다시 떠 있는 상주 작업과 중단 신호는 뺀다.
    public var failed: Bool {
        guard let e = lastExit, e != 0, !Job.isInterrupt(e) else { return false }
        return !(kind == .resident && running)
    }

    /// 같은 실패를 가리키는 키. 다시 돌아 실행 횟수나 종료 코드가 바뀌면 달라진다.
    public var failureKey: String { "\(id)|\(lastExit ?? 0)|\(runs ?? -1)" }

    /// 메뉴바 배지에 셀 것: 내 에이전트의, 아직 확인하지 않은 실패.
    public func needsAttention(acknowledged: Set<String>) -> Bool {
        failed && source == .userAgent && !acknowledged.contains(failureKey)
    }

    /// 백그라운드(launchd) 실행에서 접근이 막힐 수 있는 위치를 쓰는 인자·경로.
    public func protectedPaths(home: String) -> [String] {
        let all = args + [stdoutPath, stderrPath, workingDir].compactMap { $0 }
        return all.filter { Job.touchesProtectedFolder($0, home: home) }
    }

    /// 글자열 안에 보호 폴더 경로가 들었는지.
    public static func touchesProtectedFolder(_ text: String, home: String) -> Bool {
        let roots = ["\(home)/Desktop/", "\(home)/Documents/", "\(home)/Downloads/",
                     "\(home)/Library/Mobile Documents/", "/Volumes/"]
        // plist 안 한글 경로는 NFD로 저장돼 있을 수 있어 정규화해서 비교한다.
        // `sh -c "cd ~/Desktop/x && …"` 처럼 인자 중간에 든 경로도 잡는다.
        let n = text.precomposedStringWithCanonicalMapping
        return roots.contains { n.contains($0) }
    }

    /// 권한 함정 표시 대상인지. 데몬은 root 로 돌아 해당 없다.
    public func riskyPaths(home: String) -> [String] {
        domain == .system ? [] : protectedPaths(home: home)
    }

    public var displayProgram: String {
        guard let first = args.first else { return "-" }
        let interpreters = ["bash", "sh", "zsh", "python3", "python", "node", "ruby", "perl"]
        if interpreters.contains((first as NSString).lastPathComponent), args.count > 1 {
            if args[1] == "-c", args.count > 2 {   // sh -c "명령 ..." → 명령의 첫 단어
                let words = args[2].split(separator: " ").map(String.init).filter { $0 != "exec" }
                let cmd = words.first ?? args[2]
                return (cmd as NSString).lastPathComponent
            }
            return (args[1] as NSString).lastPathComponent
        }
        return (first as NSString).lastPathComponent
    }

    /// 상태를 직접 확인할 때 터미널에 붙여 넣는 읽기 명령.
    /// 라벨은 남이 정한 글자열이다. 터미널에 붙여 넣었을 때 다른 명령으로 읽히지 않게 필요하면 따옴표로 감싼다.
    public func inspectCommand(uid: Int) -> String {
        let target = domain == .system ? "system/\(label)" : "gui/\(uid)/\(label)"
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/")
        if target.unicodeScalars.allSatisfy(safe.contains) { return "launchctl print \(target)" }
        return "launchctl print '" + target.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct Proc: Identifiable, Hashable, Sendable {
    public let id: Int
    public let cpu: Double
    public let mem: Double
    public let elapsed: String
    public let path: String
    public var name: String { (path as NSString).lastPathComponent }

    public init(id: Int, cpu: Double, mem: Double, elapsed: String, path: String) {
        self.id = id; self.cpu = cpu; self.mem = mem; self.elapsed = elapsed; self.path = path
    }
}

public func exitDescription(_ code: Int) -> String {
    switch code {
    case 0: return "정상"
    case 1: return "오류(1)"
    case 2: return "잘못된 사용(2)"
    case 78: return "설정 오류(78)"
    case 126: return "실행 불가(126) · 파일 접근 권한 문제일 수 있음"
    case 127: return "명령을 찾지 못함(127)"
    case -9: return "강제 종료됨(SIGKILL)"
    case -15: return "종료 신호 받음(SIGTERM)"
    case let c where c < 0: return "신호로 종료(\(c))"
    default: return "오류(\(code))"
    }
}

public func statusDescription(_ s: JobStatus) -> String {
    func times(_ runs: Int?) -> String { runs.map { " · \($0)회 실행" } ?? "" }
    switch s {
    case .running(let pid): return "실행 중 · PID \(pid)"
    case .notLoaded: return "꺼짐(미등록)"
    case .disabled: return "꺼 둠"
    case .neverRan: return "아직 돈 적 없음"
    case .succeeded(let runs): return "정상" + times(runs)
    case .interrupted(let code): return "중단됨 · " + exitDescription(code)
    case .failed(let code, let runs): return exitDescription(code) + times(runs)
    case .idle: return "대기 · 실행 기록 없음"
    }
}
