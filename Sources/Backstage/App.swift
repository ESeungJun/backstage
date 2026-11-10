// Backstage: launchd 예약/상주 작업과 내 프로세스를 한 화면에 보여주는 읽기 전용 메뉴바 앱
import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - 모델

enum Source: String, CaseIterable {
    case userAgent = "내 에이전트"
    case globalAgent = "공용 에이전트"
    case daemon = "시스템 데몬"
}

enum Kind: String {
    case scheduled = "예약"
    case resident = "상주"
    case trigger = "요청 시"
    case atLogin = "로그인 시"
    case manual = "수동"
}

struct Job: Identifiable, Hashable {
    let id: String            // plist 경로
    let label: String
    let source: Source
    let kind: Kind
    let schedule: String
    let nextRun: Date?
    let args: [String]
    let stdoutPath: String?
    let stderrPath: String?
    let workingDir: String?
    let disabledInPlist: Bool
    var loaded = false
    var pid: Int?
    var lastExit: Int?        // nil = 아직 종료 기록 없음/알 수 없음

    var running: Bool { pid != nil }
    var failed: Bool { if let e = lastExit { return e != 0 && !(kind == .resident && running) } else { return false } }

    /// 보호 폴더(Desktop/Documents/Downloads) 안 파일을 쓰는지. launchd 백그라운드 실행에서 접근이 막힐 수 있다.
    var protectedPaths: [String] {
        let home = NSHomeDirectory()
        let roots = ["Desktop", "Documents", "Downloads"].map { "\(home)/\($0)/" }
        let all = args + [stdoutPath, stderrPath, workingDir].compactMap { $0 }
        // plist 안 한글 경로는 NFD로 저장돼 있을 수 있어 정규화해서 비교한다
        return all.filter { p in roots.contains { p.precomposedStringWithCanonicalMapping.hasPrefix($0) } }
    }

    var displayProgram: String {
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
}

struct Proc: Identifiable, Hashable {
    let id: Int
    let cpu: Double
    let mem: Double
    let elapsed: String
    let path: String
    var name: String { (path as NSString).lastPathComponent }
}

// MARK: - 셸 실행

func sh(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// MARK: - 일정 해석

let weekdayNames = ["일", "월", "화", "수", "목", "금", "토", "일"]

func describeCalendar(_ d: [String: Int]) -> String {
    let m = d["Minute"], h = d["Hour"], day = d["Day"], wd = d["Weekday"], mon = d["Month"]
    var when: String
    if let mon { when = "매년 \(mon)월 " + (day.map { "\($0)일" } ?? "매일") }
    else if let day { when = "매월 \(day)일" }
    else if let wd { when = "매주 \(weekdayNames[min(max(wd, 0), 7)])요일" }
    else { when = "매일" }
    if let h { return "\(when) " + String(format: "%02d:%02d", h, m ?? 0) }
    if let m { return (when == "매일" ? "" : when + " ") + "매시 \(m)분" }
    return (when == "매일" ? "" : when + " ") + "매분"
}

func nextCalendarDate(_ d: [String: Int], after now: Date) -> Date? {
    var c = DateComponents()
    c.month = d["Month"]; c.day = d["Day"]; c.hour = d["Hour"]
    c.minute = d["Minute"] ?? (d["Hour"] != nil ? 0 : nil)
    if let wd = d["Weekday"] { c.weekday = (wd % 7) + 1 }   // launchd 0/7=일 → Calendar 1=일
    if c.minute == nil && c.hour == nil && c.day == nil && c.month == nil && c.weekday == nil {
        return now.addingTimeInterval(60)
    }
    return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
}

func describeInterval(_ s: Int) -> String {
    if s % 86400 == 0 { return "\(s / 86400)일마다" }
    if s % 3600 == 0 { return "\(s / 3600)시간마다" }
    if s % 60 == 0 { return "\(s / 60)분마다" }
    return "\(s)초마다"
}

func exitDescription(_ code: Int) -> String {
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

// MARK: - 수집

func intDict(_ any: Any) -> [String: Int] {
    var r: [String: Int] = [:]
    (any as? [String: Any])?.forEach { k, v in if let n = v as? Int { r[k] = n } }
    return r
}

func loadJobs() -> [Job] {
    let home = NSHomeDirectory()
    let dirs: [(String, Source)] = [
        ("\(home)/Library/LaunchAgents", .userAgent),
        ("/Library/LaunchAgents", .globalAgent),
        ("/Library/LaunchDaemons", .daemon),
    ]
    let now = Date()
    var jobs: [Job] = []
    for (dir, src) in dirs {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for f in files where f.hasSuffix(".plist") {
            let path = "\(dir)/\(f)"
            guard let data = FileManager.default.contents(atPath: path),
                  let pl = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let label = pl["Label"] as? String ?? (f as NSString).deletingPathExtension
            var args = pl["ProgramArguments"] as? [String] ?? []
            if let prog = pl["Program"] as? String {
                if args.isEmpty { args = [prog] } else { args[0] = prog }
            }

            var kind: Kind = .manual
            var schedule = "직접 실행할 때만"
            var next: Date?
            if let cal = pl["StartCalendarInterval"] {
                let entries = (cal as? [Any])?.map(intDict) ?? [intDict(cal)]
                kind = .scheduled
                schedule = entries.map(describeCalendar).joined(separator: ", ")
                next = entries.compactMap { nextCalendarDate($0, after: now) }.min()
            } else if let iv = pl["StartInterval"] as? Int {
                kind = .scheduled
                schedule = describeInterval(iv)
            } else if let ka = pl["KeepAlive"], (ka as? Bool) == true || ka is [String: Any] {
                kind = .resident
                schedule = (ka as? Bool) == true ? "항상 실행 (죽으면 다시 켬)" : "조건부 상주"
            } else if pl["WatchPaths"] != nil || pl["QueueDirectories"] != nil || pl["MachServices"] != nil || pl["Sockets"] != nil {
                kind = .trigger
                schedule = "다른 프로그램이 요청할 때"
            } else if (pl["RunAtLoad"] as? Bool) == true {
                kind = .atLogin
                schedule = src == .daemon ? "부팅 시 1회" : "로그인 시 1회"
            }
            if kind == .scheduled, (pl["RunAtLoad"] as? Bool) == true { schedule += " · 로그인 시에도" }

            jobs.append(Job(
                id: path, label: label, source: src, kind: kind, schedule: schedule, nextRun: next,
                args: args,
                stdoutPath: pl["StandardOutPath"] as? String,
                stderrPath: pl["StandardErrorPath"] as? String,
                workingDir: pl["WorkingDirectory"] as? String,
                disabledInPlist: (pl["Disabled"] as? Bool) == true))
        }
    }

    // 사용자 도메인 상태: launchctl list (PID, 마지막 종료 코드, 라벨)
    var userState: [String: (Int?, Int?)] = [:]
    for line in sh("/bin/launchctl", ["list"]).split(separator: "\n").dropFirst() {
        let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 3 else { continue }
        userState[cols[2]] = (Int(cols[0]), Int(cols[1]))
    }
    for i in jobs.indices {
        if jobs[i].source == .daemon {
            let out = sh("/bin/launchctl", ["print", "system/\(jobs[i].label)"])
            guard !out.isEmpty, !out.contains("Could not find service") else { continue }
            jobs[i].loaded = true
            for raw in out.split(separator: "\n") {
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("pid = ") { jobs[i].pid = Int(l.dropFirst(6)) }
                if l.hasPrefix("last exit code = ") { jobs[i].lastExit = Int(l.dropFirst(17)) }
            }
        } else if let st = userState[jobs[i].label] {
            jobs[i].loaded = true
            jobs[i].pid = st.0
            // 한 번도 안 돈 작업도 0으로 나오므로, print로 never exited 여부 확인은 생략하고 0은 정상으로 본다
            jobs[i].lastExit = st.1
        }
    }
    return jobs
}

func loadProcesses() -> [Proc] {
    let me = NSUserName()
    var procs: [Proc] = []
    for line in sh("/bin/ps", ["-axo", "pid=,user=,%cpu=,%mem=,etime=,comm="]).split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 6, parts[1] == me, let pid = Int(parts[0]) else { continue }
        let path = parts[5]
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") { continue }
        procs.append(Proc(id: pid, cpu: Double(parts[2]) ?? 0, mem: Double(parts[3]) ?? 0, elapsed: parts[4], path: path))
    }
    return procs.sorted { $0.cpu == $1.cpu ? $0.mem > $1.mem : $0.cpu > $1.cpu }
}

func tail(_ path: String?, bytes: Int = 4000) -> String {
    guard let path, let fh = FileHandle(forReadingAtPath: path) else { return "" }
    defer { try? fh.close() }
    let size = (try? fh.seekToEnd()) ?? 0
    try? fh.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
    let data = (try? fh.readToEnd()) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

// MARK: - 상태 저장소

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var procs: [Proc] = []
    @Published var updated = Date()
    @Published var loading = false
    private var timer: Timer?
    let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo { jobs = demoJobs(); procs = demoProcs(); return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !demo, !loading else { return }
        loading = true
        Task.detached {
            let j = loadJobs()
            let p = loadProcesses()
            await MainActor.run {
                self.jobs = j
                self.procs = p
                self.updated = Date()
                self.loading = false
            }
        }
    }
}

// MARK: - 데모 데이터 (README 스크린샷용, --demo)

func demoJobs() -> [Job] {
    let now = Date()
    let home = NSHomeDirectory()
    func next(_ d: [String: Int]) -> Date? { nextCalendarDate(d, after: now) }
    func job(_ label: String, _ kind: Kind, _ schedule: String, _ next: Date?, _ args: [String],
             src: Source = .userAgent, pid: Int? = nil, exit: Int? = 0, log: String? = nil) -> Job {
        var j = Job(id: "\(home)/Library/LaunchAgents/\(label).plist", label: label, source: src, kind: kind,
                    schedule: schedule, nextRun: next, args: args, stdoutPath: log, stderrPath: log,
                    workingDir: nil, disabledInPlist: false)
        j.loaded = true; j.pid = pid; j.lastExit = exit
        return j
    }
    return [
        job("com.example.photo-backup", .scheduled, "매일 02:30", next(["Hour": 2, "Minute": 30]),
            ["/bin/bash", "\(home)/Desktop/scripts/backup.sh"], exit: 126),
        job("com.example.daily-post", .scheduled, "매일 19:07", next(["Hour": 19, "Minute": 7]),
            ["/bin/bash", "\(home)/Projects/daily-post/run_daily.sh"]),
        job("com.example.weekly-report", .scheduled, "매주 월요일 09:10", next(["Weekday": 1, "Hour": 9, "Minute": 10]),
            ["/usr/bin/python3", "\(home)/Projects/report/weekly.py"]),
        job("com.example.monthly-invoice", .scheduled, "매월 1일 09:20", next(["Day": 1, "Hour": 9, "Minute": 20]),
            ["/bin/bash", "\(home)/Projects/invoice/run.sh"]),
        job("com.example.sync", .scheduled, "30분마다", nil, ["/usr/local/bin/node", "\(home)/Projects/sync/index.js"]),
        job("com.example.notes-server", .resident, "항상 실행 (죽으면 다시 켬)", nil,
            ["/usr/local/bin/node", "\(home)/Documents/notes/server.js"], pid: 4821),
        job("com.example.dev-proxy", .resident, "항상 실행 (죽으면 다시 켬)", nil,
            ["/opt/homebrew/bin/caddy", "run"], pid: 1093),
        job("com.google.keystone.agent", .scheduled, "1시간마다", nil,
            ["/Library/Google/GoogleSoftwareUpdate/GoogleSoftwareUpdateAgent"], src: .globalAgent),
        job("com.docker.vmnetd", .trigger, "다른 프로그램이 요청할 때", nil,
            ["/Library/PrivilegedHelperTools/com.docker.vmnetd"], src: .daemon, pid: 334),
        job("com.example.updater", .atLogin, "로그인 시 1회", nil, ["/Applications/Example.app/Contents/MacOS/updater"], exit: nil),
    ]
}

func demoProcs() -> [Proc] {
    [("Google Chrome Helper", 18.2, 3.1), ("node", 6.4, 1.2), ("Code Helper (Renderer)", 4.9, 2.4),
     ("Docker", 2.1, 4.8), ("Slack Helper", 1.3, 1.5), ("caddy", 0.4, 0.2), ("Backstage", 0.3, 0.3)]
        .enumerated().map { i, t in Proc(id: 4000 + i * 37, cpu: t.1, mem: t.2, elapsed: "0\(i + 1):12:44", path: "/Applications/\(t.0)") }
}

// MARK: - 화면

enum Filter: String, CaseIterable, Identifiable {
    case all = "전체", scheduled = "예약", resident = "상주", problem = "문제", mine = "내 에이전트만"
    var id: String { rawValue }
}

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

struct StatusDot: View {
    let job: Job
    var color: Color {
        if job.failed { return .red }
        if job.running { return .green }
        if !job.loaded { return .gray }
        if !job.protectedPaths.isEmpty && job.source != .daemon { return .orange }
        return .blue
    }
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}

struct Card: View {
    let title: String
    let value: String
    let sub: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct JobsView: View {
    @ObservedObject var store: Store
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var selection: Job.ID?
    @State private var didPreselect = false

    var filtered: [Job] {
        store.jobs.filter { j in
            switch filter {
            case .all: true
            case .scheduled: j.kind == .scheduled
            case .resident: j.kind == .resident
            case .problem: j.failed || (!j.protectedPaths.isEmpty && j.source != .daemon)
            case .mine: j.source == .userAgent
            }
        }
        .filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.args.joined(separator: " ").localizedCaseInsensitiveContains(query) }
        .sorted { a, b in
            if a.failed != b.failed { return a.failed }
            switch (a.nextRun, b.nextRun) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.label < b.label
            }
        }
    }

    var body: some View {
        let scheduled = store.jobs.filter { $0.kind == .scheduled }
        let next = scheduled.filter { $0.nextRun != nil }.min { $0.nextRun! < $1.nextRun! }
        let running = store.jobs.filter { $0.running }
        let failed = store.jobs.filter { $0.failed }
        let risky = store.jobs.filter { !$0.protectedPaths.isEmpty && $0.source != .daemon }

        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Card(title: "예약 작업", value: "\(scheduled.count)개",
                     sub: next.map { "다음: \($0.label) · \(relFormatter.localizedString(for: $0.nextRun!, relativeTo: Date()))" } ?? "예정 없음",
                     tint: .primary)
                Card(title: "지금 실행 중", value: "\(running.count)개",
                     sub: running.prefix(3).map(\.displayProgram).joined(separator: ", "), tint: .green)
                Card(title: "마지막 실행 실패", value: "\(failed.count)개",
                     sub: failed.isEmpty ? "모두 정상" : failed.prefix(3).map(\.label).joined(separator: ", "),
                     tint: failed.isEmpty ? .secondary : .red)
                Card(title: "권한 막힘 위험", value: "\(risky.count)개",
                     sub: "Desktop·Documents·Downloads 안의 파일 사용", tint: risky.isEmpty ? .secondary : .orange)
            }

            HStack {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Spacer()
                TextField("이름·경로 검색", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
            }

            HSplitView {
                Table(filtered, selection: $selection) {
                    TableColumn("") { j in StatusDot(job: j) }.width(16)
                    TableColumn("이름") { j in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(j.label).fontWeight(.medium)
                            Text(j.displayProgram).font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(min: 170, ideal: 215)
                    TableColumn("종류") { j in Text(j.kind.rawValue) }.width(55)
                    TableColumn("일정") { j in Text(j.schedule).lineLimit(2) }.width(min: 110, ideal: 145)
                    TableColumn("다음 실행") { j in
                        if let n = j.nextRun {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(timeFormatter.string(from: n))
                                Text(relFormatter.localizedString(for: n, relativeTo: Date())).font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("-").foregroundStyle(.secondary) }
                    }.width(min: 100, ideal: 120)
                    TableColumn("상태") { j in
                        if j.running { Text("실행 중 · PID \(j.pid!)").foregroundStyle(.green) }
                        else if !j.loaded { Text("꺼짐(미등록)").foregroundStyle(.secondary) }
                        else if let e = j.lastExit { Text(exitDescription(e)).foregroundStyle(j.failed ? .red : .primary) }
                        else { Text("대기") }
                    }.width(min: 110, ideal: 150)
                    TableColumn("출처") { j in Text(j.source.rawValue).foregroundStyle(.secondary) }.width(80)
                }
                .frame(minWidth: 820)

                Group {
                    if let id = selection, let job = store.jobs.first(where: { $0.id == id }) {
                        JobDetail(job: job)
                    } else {
                        Text("작업을 고르면 자세히 보여줍니다").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
        }
        .padding(14)
        .onReceive(store.$jobs) { jobs in
            guard store.demo, !didPreselect, let first = jobs.first(where: \.failed) else { return }
            selection = first.id; didPreselect = true
        }
    }
}

struct JobDetail: View {
    let job: Job
    @State private var logText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { StatusDot(job: job); Text(job.label).font(.title3.weight(.semibold)).textSelection(.enabled) }

                if !job.protectedPaths.isEmpty && job.source != .daemon {
                    Label {
                        Text("보호 폴더 안의 파일을 씁니다. 백그라운드(launchd) 실행에서는 macOS가 접근을 막아 '실행 불가(126)'나 'Operation not permitted'로 실패할 수 있습니다. 폴더를 ~/Projects 같은 곳으로 옮기면 해결됩니다.")
                    } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    .font(.callout)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }

                info("일정", job.schedule)
                if let n = job.nextRun { info("다음 실행", "\(timeFormatter.string(from: n)) (\(relFormatter.localizedString(for: n, relativeTo: Date())))") }
                info("상태", job.running ? "실행 중 (PID \(job.pid!))" : (job.loaded ? (job.lastExit.map(exitDescription) ?? "대기") : "등록 안 됨 (launchctl에 로드되지 않음)"))
                info("실행 명령", job.args.joined(separator: " "))
                if let w = job.workingDir { info("작업 폴더", w) }
                info("설정 파일", job.id)

                HStack {
                    Button("설정 파일 Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.id)]) }
                    if let log = job.stderrPath ?? job.stdoutPath {
                        Button("로그 열기") { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
                    }
                }

                if job.stderrPath != nil || job.stdoutPath != nil {
                    Text("최근 로그").font(.headline)
                    Text(logText.isEmpty ? "(비어 있음 또는 읽을 수 없음)" : logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: job.id) { loadLog() }
    }

    func loadLog() {
        var parts: [String] = []
        let err = tail(job.stderrPath, bytes: 2500)
        let out = job.stdoutPath == job.stderrPath ? "" : tail(job.stdoutPath, bytes: 2500)
        if !err.isEmpty { parts.append(job.stdoutPath == job.stderrPath ? err : "[stderr]\n" + err) }
        if !out.isEmpty { parts.append("[stdout]\n" + out) }
        logText = parts.joined(separator: "\n\n")
    }

    func info(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}

struct ProcsView: View {
    @ObservedObject var store: Store
    @State private var query = ""

    var body: some View {
        let list = store.procs.filter { query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 10) {
            HStack {
                Text("내 계정으로 실행 중인 프로그램 \(store.procs.count)개 (macOS 기본 시스템 프로세스 제외, CPU 순)")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("이름·경로 검색", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            Table(list) {
                TableColumn("이름") { p in Text(p.name).fontWeight(.medium) }.width(min: 160, ideal: 220)
                TableColumn("CPU %") { p in Text(String(format: "%.1f", p.cpu)).foregroundStyle(p.cpu > 50 ? .red : .primary) }.width(60)
                TableColumn("메모리 %") { p in Text(String(format: "%.1f", p.mem)) }.width(70)
                TableColumn("실행 시간") { p in Text(p.elapsed) }.width(90)
                TableColumn("PID") { p in Text("\(p.id)").foregroundStyle(.secondary) }.width(60)
                TableColumn("경로") { p in Text(p.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
        .padding(14)
    }
}

/// 로그인할 때 자동으로 켜기 (macOS 로그인 항목, SMAppService)
struct LoginToggle: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        Toggle("로그인 시 실행", isOn: Binding(get: { on }, set: { want in
            do {
                if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                error = nil
            } catch { self.error = error.localizedDescription }
            on = SMAppService.mainApp.status == .enabled
        }))
        .toggleStyle(.checkbox)
        .help(error ?? "맥에 로그인하면 Backstage를 메뉴바에 자동으로 띄웁니다")
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

struct ContentView: View {
    @ObservedObject var store: Store
    var size = CGSize(width: 1320, height: 780)
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("예약·상주 작업").tag(0)
                    Text("실행 중인 프로그램").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Text("갱신 \(store.updated.formatted(date: .omitted, time: .standard)) · 15초마다")
                    .font(.caption).foregroundStyle(.secondary)
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help("새로고침 (⌘R)")
                Divider().frame(height: 16)
                LoginToggle()
                Text("v\(appVersion)").font(.caption).foregroundStyle(.tertiary)
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .help("앱 종료 (⌘Q)")
            }
            .padding(.horizontal, 14).padding(.top, 12)

            if tab == 0 { JobsView(store: store) } else { ProcsView(store: store) }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 메뉴바 아이콘 + 클릭하면 펼쳐지는 팝오버
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let store = Store(demo: CommandLine.arguments.contains("--demo"))
    private var window: NSWindow?
    private var cancel: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading

        popover.behavior = .transient          // 바깥을 누르면 닫힘
        popover.animates = false
        // 작은 화면에서도 넘치지 않게 화면 크기에 맞춘다
        let vis = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let size = CGSize(width: min(1320, vis.width - 40), height: min(780, vis.height - 40))
        popover.contentSize = size
        popover.contentViewController = NSHostingController(rootView: ContentView(store: store, size: size))

        // 처음 켰을 때 한 번만 로그인 항목으로 등록한다 (끄면 다시 켜지 않음)
        let key = "didRegisterLoginItem"
        // dmg 안에서 바로 실행한 경우 등록하면 로그인 항목이 dmg 경로를 가리키게 되므로, 응용 프로그램 폴더에 있을 때만
        let path = Bundle.main.bundlePath
        let installed = path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        if installed, !UserDefaults.standard.bool(forKey: key), !store.demo {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        }

        // 스크린샷용: 팝오버 대신 일반 창으로 띄운다
        if CommandLine.arguments.contains("--window") {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Backstage"
            w.contentViewController = NSHostingController(rootView: ContentView(store: store, size: size))
            w.center(); w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window = w
        }

        cancel = store.$jobs.receive(on: RunLoop.main).sink { [weak self] jobs in self?.updateIcon(jobs) }
        updateIcon([])
    }

    /// 실패한 작업이 있으면 경고 아이콘 + 개수, 없으면 시계 아이콘
    private func updateIcon(_ jobs: [Job]) {
        let failed = jobs.filter(\.failed).count
        let name = failed > 0 ? "exclamationmark.triangle.fill" : "clock.arrow.2.circlepath"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Backstage")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.title = failed > 0 ? " \(failed)" : ""
        item.button?.toolTip = failed > 0 ? "마지막 실행이 실패한 작업 \(failed)개" : "Backstage"
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@main
struct BackstageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
