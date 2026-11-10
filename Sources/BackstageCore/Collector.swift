import Foundation

// MARK: - 바깥과 닿는 곳 (테스트에서 바꿔 끼운다)

public protocol CommandRunner: Sendable {
    /// 명령을 실행해 표준 출력을 돌려준다. 실패·시간 초과면 빈 문자열.
    func run(_ exe: String, _ args: [String]) -> String
}

public protocol FileSource: Sendable {
    func list(_ dir: String) -> [String]
    func contents(_ path: String) -> Data?
    func exists(_ path: String) -> Bool
}

public struct DiskFiles: FileSource {
    public init() {}
    public func list(_ dir: String) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] }
    public func contents(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }
    public func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// 실제 프로세스를 띄운다. 응답이 없으면 제한 시간 뒤에 끊는다. 띄운 횟수를 센다(비용 측정용).
public final class ProcessRunner: CommandRunner, @unchecked Sendable {
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var count = 0

    public init(timeout: TimeInterval = 5) { self.timeout = timeout }

    public var spawnCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    public func run(_ exe: String, _ args: [String]) -> String {
        lock.lock(); count += 1; lock.unlock()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice   // 읽지 않는 파이프가 차서 멈추지 않게
        // waitUntilExit 는 런루프를 돌려 호출마다 수십 ms 가 더 든다. 종료 알림을 직접 기다린다.
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return "" }
        // 제한 시간이 지나면 끊는다. 끊기면 파이프가 닫혀 아래 읽기가 풀린다.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 수집

/// 서비스별 상세 출력을 다시 읽지 않기 위한 기억. 같은 PID 로 계속 돌고 있으면 실행 횟수가 바뀔 수 없다.
public struct DetailCache: Sendable {
    public struct Entry: Sendable {
        public var detail: ServiceDetail
        public var pid: Int?
    }
    public var entries: [String: Entry] = [:]
    /// macOS 기본 서비스로 판명돼 목록에서 뺀 것. 다시 묻지 않는다.
    public var builtin: Set<String> = []
    /// 마지막 수집에서 사용자 도메인 목록을 읽었는지. 못 읽었으면 그 결과로 기록·기준선을 고치지 않는다.
    public var domainRead = false
    public init() {}
}

public struct Collector: Sendable {
    public let runner: CommandRunner
    public let files: FileSource
    public let home: String
    public let uid: Int

    public init(runner: CommandRunner, files: FileSource = DiskFiles(), home: String, uid: Int) {
        self.runner = runner; self.files = files; self.home = home; self.uid = uid
    }

    var folders: [(String, Source)] {
        [("\(home)/Library/LaunchAgents", .userAgent),
         ("/Library/LaunchAgents", .globalAgent),
         ("/Library/LaunchDaemons", .daemon)]
    }

    /// 세 폴더의 plist 와 launchd 에 올라온 서비스 목록을 합친다.
    public func collectJobs(now: Date, cache: inout DetailCache) -> [Job] {
        var jobs: [Job] = []
        var extra: [String: [String]] = [:]   // id → plist 가 적은 번들 ID

        // 1) 세 폴더의 설정 파일. 읽지 못해도 빼지 않는다.
        for (dir, src) in folders {
            for f in files.list(dir).sorted() where f.hasSuffix(".plist") {
                let path = "\(dir)/\(f)"
                let domain: Domain = src == .daemon ? .system : .gui
                let fallback = (f as NSString).deletingPathExtension
                if let data = files.contents(path), let info = parsePlist(data, system: domain == .system, now: now) {
                    let label = info.label ?? fallback
                    var j = Job(id: Job.makeID(domain, label), label: label, source: src, domain: domain,
                                kind: info.kind, schedule: info.schedule, nextRun: info.nextRun, args: info.args,
                                stdoutPath: info.stdoutPath, stderrPath: info.stderrPath, workingDir: info.workingDir,
                                plistPath: path)
                    j.plistReadable = true
                    extra[j.id] = info.associatedBundleIDs
                    jobs.append(j)
                } else {
                    // 관리자 전용이거나 깨진 파일. 파일 이름을 라벨로 보고 상태만 launchctl 에서 채운다.
                    var j = Job(id: Job.makeID(domain, fallback), label: fallback, source: src, domain: domain,
                                kind: .unknown,
                                schedule: files.contents(path) == nil ? "설정 파일을 읽을 수 없음(관리자 전용)" : "설정 파일을 해석할 수 없음",
                                plistPath: path)
                    j.plistReadable = false
                    jobs.append(j)
                }
            }
        }

        // 2) 도메인마다 한 번씩만 읽는다: 로드된 서비스 전체의 PID·종료 코드, 꺼 둔 서비스 목록.
        let snaps: [Domain: DomainSnapshot] = [
            .gui: parseDomainPrint(runner.run("/bin/launchctl", ["print", "gui/\(uid)"])),
            .system: parseDomainPrint(runner.run("/bin/launchctl", ["print", "system"])),
        ]

        // 3) 설정 파일이 세 폴더에 없는 서비스. Apple 것과 일반 앱 실행(application.*)은 뺀다.
        var known = Set(jobs.map(\.id))
        for domain in [Domain.gui, .system] {
            for label in (snaps[domain]?.services.keys.sorted() ?? []) where Collector.isThirdParty(label) {
                let id = Job.makeID(domain, label)
                guard !cache.builtin.contains(id), known.insert(id).inserted else { continue }
                jobs.append(Job(id: id, label: label, source: .appEmbedded, domain: domain, kind: .unknown,
                                schedule: "설정 파일 없이 등록됨"))
            }
        }

        // 4) 상태를 채우고, 필요한 것만 서비스별 상세를 읽는다.
        var fresh = DetailCache()
        fresh.builtin = cache.builtin
        fresh.domainRead = !(snaps[.gui]?.services.isEmpty ?? true)
        var builtin: Set<Int> = []
        for i in jobs.indices {
            let snap = snaps[jobs[i].domain] ?? DomainSnapshot()
            jobs[i].disabled = snap.disabled.contains(jobs[i].label)
            guard let row = snap.services[jobs[i].label] else { continue }
            jobs[i].loaded = true
            jobs[i].pid = row.pid
            jobs[i].lastExit = row.lastExit

            let detail: ServiceDetail?
            if let c = cache.entries[jobs[i].id], let pid = row.pid, c.pid == pid {
                detail = c.detail
            } else {
                let target = jobs[i].domain == .system ? "system/\(jobs[i].label)" : "gui/\(uid)/\(jobs[i].label)"
                detail = parseServicePrint(runner.run("/bin/launchctl", ["print", target]))
            }
            guard let d = detail else { continue }
            fresh.entries[jobs[i].id] = .init(detail: d, pid: row.pid)
            // 라벨이 com.apple 로 시작하지 않아도 /System 아래 plist 로 올라온 것은 macOS 기본 서비스다
            if jobs[i].source == .appEmbedded, d.plistPath?.hasPrefix("/System/") == true {
                builtin.insert(i); fresh.builtin.insert(jobs[i].id); fresh.entries[jobs[i].id] = nil
                continue
            }
            apply(d, to: &jobs[i], now: now, associated: &extra)
        }
        cache = fresh

        // 5) 출처
        for i in jobs.indices {
            let d = fresh.entries[jobs[i].id]?.detail
            let paths = [d?.plistPath, d?.program].compactMap { $0 } + jobs[i].args
            jobs[i].owner = resolveOwner(associated: extra[jobs[i].id] ?? [],
                                         parentBundleID: d?.parentBundleID ?? d?.bundleID,
                                         paths: paths, source: jobs[i].source, home: home)
            if case .app(let path) = jobs[i].owner { jobs[i].ownerMissing = !files.exists(path) }
        }

        // 6) 읽지 못한 설정 파일의 실제 라벨이 파일 이름과 다르면, 3)에서 따로 잡힌 서비스와 같은 것이다. 하나로 합친다.
        var placeholders: [String: Int] = [:]
        for i in jobs.indices where jobs[i].source != .appEmbedded && !jobs[i].plistReadable && !jobs[i].loaded {
            if let p = jobs[i].plistPath { placeholders[p] = i }
        }
        var drop = builtin
        for i in jobs.indices where jobs[i].source == .appEmbedded {
            guard let p = jobs[i].plistPath, let twin = placeholders[p] else { continue }
            jobs[i].source = jobs[twin].source
            drop.insert(twin)
        }
        return jobs.indices.filter { !drop.contains($0) }.map { jobs[$0] }
    }

    /// 상세 출력으로 빈 곳을 메운다. plist 에서 읽은 값이 있으면 그 값을 둔다.
    func apply(_ d: ServiceDetail, to job: inout Job, now: Date, associated: inout [String: [String]]) {
        job.runs = d.runs
        job.neverExited = d.neverExited
        if let e = d.lastExit { job.lastExit = e }
        if job.args.isEmpty { job.args = d.commandLine }
        if job.stdoutPath == nil { job.stdoutPath = d.stdoutPath }
        if job.stderrPath == nil { job.stderrPath = d.stderrPath }
        if job.workingDir == nil { job.workingDir = d.workingDir }
        guard job.plistPath == nil else { return }
        // 세 폴더 밖(주로 앱 번들 안)의 plist 로 등록된 서비스: 그 파일에서 일정을 읽는다.
        if let path = d.plistPath {
            job.plistPath = path
            if let data = files.contents(path), let info = parsePlist(data, system: job.domain == .system, now: now) {
                job.kind = info.kind; job.schedule = info.schedule; job.nextRun = info.nextRun
                if !info.args.isEmpty { job.args = info.args }
                associated[job.id] = info.associatedBundleIDs
            } else if files.exists(path) {
                job.plistReadable = false
                job.schedule = "설정 파일을 읽을 수 없음"
            } else {
                // 임시 설정 파일로 올린 뒤 파일을 지운 경우
                job.plistPath = nil
                job.origin = "임시 설정 파일로 등록됨(지금은 파일 없음)"
            }
        } else if let who = d.submittedBy {
            job.origin = d.managedBy == "com.apple.xpc.ServiceManagement"
                ? "앱이 로그인 항목·도우미로 등록(\(who))" : "프로그램이 실행 중에 직접 등록(\(who))"
        }
    }

    /// Apple 서비스와 일반 앱 실행은 "뒤에서 심긴 것"이 아니다.
    static func isThirdParty(_ label: String) -> Bool {
        !label.hasPrefix("com.apple.") && !label.hasPrefix("application.")
    }

    public func collectProcesses() -> [Proc] {
        parseProcesses(runner.run("/bin/ps", ["-axo", "pid=,uid=,%cpu=,%mem=,etime=,comm="]), uid: uid)
    }
}

/// 로그 파일의 끝부분. 바이트 중간에서 잘린 첫 줄은 버린다.
public func tail(_ path: String?, bytes: Int = 4000) -> String {
    // 일반 파일만 읽는다. 로그 경로가 장치·파이프면 읽기가 끝나지 않을 수 있다.
    guard let path,
          (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeRegular,
          let fh = FileHandle(forReadingAtPath: path) else { return "" }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    let cut = size > UInt64(bytes)
    try? fh.seek(toOffset: cut ? size - UInt64(bytes) : 0)
    var data = (try? fh.readToEnd()) ?? Data()
    if cut, let nl = data.firstIndex(of: 0x0A) { data = data[data.index(after: nl)...] }
    return String(decoding: data, as: UTF8.self)
}

/// 로그 파일이 마지막으로 바뀐 때. 실행 기록이 없을 때 "언제쯤 돌았나"의 근거로 쓴다.
public func lastLogChange(_ paths: [String?]) -> Date? {
    paths.compactMap { $0 }.filter { !$0.hasPrefix("/dev/") }.compactMap {
        (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
    }.max()
}
