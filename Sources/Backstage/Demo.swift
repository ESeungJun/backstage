import Foundation
import BackstageCore

// 예시 데이터 (README 스크린샷용, --demo). 계정 이름이 찍히지 않게 홈은 /Users/you 로 고정한다.

struct DemoData {
    var jobs: [Job]
    var summaries: [String: RunSummary]
    var newIDs: Set<String>
}

func demoData() -> DemoData {
    let now = Date()
    let home = "/Users/you"
    func next(_ d: [String: Int]) -> Date? { nextCalendarDate(d, after: now) }
    func job(_ label: String, _ kind: Kind, _ schedule: String, _ next: Date?, _ args: [String],
             src: Source = .userAgent, pid: Int? = nil, exit: Int? = 0, runs: Int? = 1, log: String? = nil,
             owner: Owner = .selfMade, plist: Bool = true) -> Job {
        let domain: Domain = src == .daemon ? .system : .gui
        let dir = src == .userAgent ? "\(home)/Library/LaunchAgents" : (src == .daemon ? "/Library/LaunchDaemons" : "/Library/LaunchAgents")
        var j = Job(id: Job.makeID(domain, label), label: label, source: src, domain: domain, kind: kind,
                    schedule: schedule, nextRun: next, args: args, stdoutPath: log, stderrPath: log,
                    plistPath: plist ? "\(dir)/\(label).plist" : nil)
        j.loaded = true; j.pid = pid; j.lastExit = exit; j.runs = runs; j.owner = owner
        j.neverExited = runs == 0 || (pid != nil && runs == 1)
        return j
    }
    var locked = job("com.example.vpn.helper", .unknown, "설정 파일을 읽을 수 없음(관리자 전용)", nil,
                     ["/Library/PrivilegedHelperTools/com.example.vpn.helper"], src: .daemon, pid: 412, exit: nil,
                     owner: .unknown)
    locked.plistReadable = false
    var login = job("com.example.clipboard.helper", .unknown, "설정 파일 없이 등록됨", nil,
                    ["Contents/Library/LoginItems/ClipHelper.app"], src: .appEmbedded, pid: 2210, exit: nil,
                    owner: .bundleID("com.example.clipboard"), plist: false)
    login.origin = "앱이 로그인 항목·도우미로 등록(smd)"
    var off = job("com.example.old-sync", .scheduled, "매일 06:00", nil, ["/bin/bash", "\(home)/Projects/old/sync.sh"], runs: nil)
    off.loaded = false; off.disabled = true; off.lastExit = nil

    let jobs = [
        job("com.example.photo-backup", .scheduled, "매일 02:30", next(["Hour": 2, "Minute": 30]),
            ["/bin/bash", "\(home)/Desktop/scripts/backup.sh"], exit: 126, runs: 41),
        job("com.example.daily-post", .scheduled, "매일 19:07", next(["Hour": 19, "Minute": 7]),
            ["/bin/bash", "\(home)/Projects/daily-post/run_daily.sh"], runs: 686),
        job("com.example.weekly-report", .scheduled, "매주 월요일 09:10", next(["Weekday": 1, "Hour": 9, "Minute": 10]),
            ["/usr/bin/python3", "\(home)/Projects/report/weekly.py"], runs: 12),
        job("com.example.monthly-invoice", .scheduled, "매월 1일 09:20", next(["Day": 1, "Hour": 9, "Minute": 20]),
            ["/bin/bash", "\(home)/Projects/invoice/run.sh"], runs: 0),
        job("com.example.sync", .scheduled, "30분마다", nil, ["/usr/local/bin/node", "\(home)/Projects/sync/index.js"], runs: 2210),
        job("com.example.notes-server", .resident, "항상 실행 (죽으면 다시 켬)", nil,
            ["/usr/local/bin/node", "\(home)/Documents/notes/server.js"], pid: 4821, exit: nil),
        job("com.example.dev-proxy", .resident, "항상 실행 (죽으면 다시 켬)", nil,
            ["/opt/homebrew/bin/caddy", "run"], pid: 1093, exit: -15, runs: 3, owner: .unknown),
        job("com.example.browser.updater", .scheduled, "1시간마다", nil,
            ["/Applications/Example Browser.app/Contents/Helpers/updater"], src: .globalAgent, runs: 129,
            owner: .app(path: "/Applications/Example Browser.app")),
        job("com.example.containers.netd", .trigger, "다른 프로그램이 요청할 때", nil,
            ["/Library/PrivilegedHelperTools/com.example.containers.netd"], src: .daemon, pid: 334, exit: nil,
            owner: .bundleID("com.example.containers")),
        login, locked, off,
    ]

    var summaries: [String: RunSummary] = [:]
    func summary(_ label: String, ago: TimeInterval, recent: [Int?]) {
        var s = RunSummary()
        s.lastAt = now.addingTimeInterval(-ago); s.lastExit = recent.last ?? nil; s.recent = recent
        s.succeeded = recent.filter { $0 == 0 }.count
        s.failed = recent.filter { $0 != nil && $0 != 0 }.count
        summaries[Job.makeID(.gui, label)] = s
    }
    summary("com.example.photo-backup", ago: 15 * 3600, recent: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 126, 126, 126])
    summary("com.example.daily-post", ago: 22 * 3600, recent: Array(repeating: 0, count: 14))
    summary("com.example.weekly-report", ago: 30 * 3600, recent: [0, 0, 1, 0, 0])
    summary("com.example.sync", ago: 11 * 60, recent: [0, 0, 0, 0, nil, nil, 0, 0, 0, 0, 0, 0, 0, 0])
    return DemoData(jobs: jobs, summaries: summaries, newIDs: [login.id])
}

func demoProcs() -> [Proc] {
    [("Example Browser Helper", 18.2, 3.1), ("node", 6.4, 1.2), ("Editor Helper (Renderer)", 4.9, 2.4),
     ("Containers", 2.1, 4.8), ("Chat Helper", 1.3, 1.5), ("caddy", 0.4, 0.2), ("Backstage", 0.3, 0.3)]
        .enumerated().map { i, t in Proc(id: 4000 + i * 37, cpu: t.1, mem: t.2, elapsed: "0\(i + 1):12:44", path: "/Applications/\(t.0)") }
}
