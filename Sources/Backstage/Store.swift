import Foundation
import Combine
import BackstageCore

/// 공식 설치본과 개발·시험 실행이 기록·설정을 섞어 쓰지 않게 폴더를 나눈다.
func dataDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["BACKSTAGE_DATA_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override)
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let official = Bundle.main.bundleIdentifier == "kr.haul.backstage"
    return base.appendingPathComponent(official ? "Backstage" : "Backstage-dev")
}

/// 수집 한 번의 결과. 백그라운드에서 만들어 메인으로 넘긴다.
struct Collected: Sendable {
    var jobs: [Job]
    var cache: DetailCache
    var summaries: [String: RunSummary]
    var baseline: Baseline?
    var arrivals: [String]
    var logChanged: [String: Date]
    var procs: [Proc]?
}

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var procs: [Proc] = []
    @Published var summaries: [String: RunSummary] = [:]
    @Published var logChanged: [String: Date] = [:]
    @Published var newIDs: Set<String> = []
    @Published var acknowledged: Set<String>
    @Published var updated: Date?
    @Published var loading = false
    @Published var selection: Job.ID?

    let demo: Bool
    let home: String
    let uid = Int(getuid())
    /// 새 항목이 생겼을 때(기준선과 비교) 불린다.
    var onArrivals: (([Job]) -> Void)?

    private let runner = ProcessRunner()
    private var cache = DetailCache()
    private var history: HistoryStore?
    private var baseline: Baseline?
    private var baselineURL: URL?
    private var slowTimer: Timer?
    private var fastTimer: Timer?
    private var viewers = 0
    private var procViewers = 0
    private var pending = false

    static let ackKey = "acknowledgedFailures"
    /// 아무도 보고 있지 않을 때의 갱신 주기(배지·기록부·새 항목 확인용)
    static let idleInterval: TimeInterval = 300
    /// 패널이나 창이 열려 있을 때의 갱신 주기
    static let activeInterval: TimeInterval = 30

    init(demo: Bool = false) {
        self.demo = demo
        self.home = demo ? "/Users/you" : NSHomeDirectory()
        self.acknowledged = Set(demo ? [] : (UserDefaults.standard.stringArray(forKey: Store.ackKey) ?? []))
        if demo {
            let d = demoData()
            jobs = d.jobs; procs = demoProcs(); summaries = d.summaries; newIDs = d.newIDs
            updated = Date()
            return
        }
        let dir = dataDirectory()
        history = HistoryStore(dir: dir)
        baselineURL = dir.appendingPathComponent("baseline.json")
        baseline = baselineURL.flatMap(loadBaseline)
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: Store.idleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 60   // 깨어나는 시각을 시스템이 다른 타이머와 묶을 수 있게
        slowTimer = t
    }

    var attention: [Job] { jobs.filter { $0.needsAttention(acknowledged: acknowledged) } }

    /// 패널·창이 열리고 닫힐 때 부른다. 열려 있는 동안만 자주 갱신한다.
    func setViewing(_ on: Bool) {
        viewers = max(0, viewers + (on ? 1 : -1))
        guard !demo else { return }
        if viewers > 0, fastTimer == nil {
            refresh()
            let t = Timer.scheduledTimer(withTimeInterval: Store.activeInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            t.tolerance = 5
            fastTimer = t
        } else if viewers == 0 {
            fastTimer?.invalidate(); fastTimer = nil
        }
    }

    /// 프로그램 탭이 보일 때만 ps 를 돈다.
    func setViewingProcs(_ on: Bool) {
        procViewers = max(0, procViewers + (on ? 1 : -1))
        if on { refresh() }
    }

    func refresh() {
        guard !demo else { return }
        guard !loading else { pending = true; return }   // 도는 중이면 끝난 뒤 한 번 더
        loading = true
        let collector = Collector(runner: runner, home: home, uid: uid)
        let history = self.history, wantProcs = procViewers > 0
        let startCache = self.cache
        let old = baseline
        Task.detached(priority: .utility) {
            let now = Date()
            var cache = startCache
            let jobs = collector.collectJobs(now: now, cache: &cache)
            // launchctl 이 답하지 않은 회차의 결과로 기록·기준선을 고치면 다음에 전부 "새 항목"이 된다
            var baseline = old, arrivals: [String] = []
            if cache.domainRead {
                history?.observe(jobs, now: now)
                let r = updateBaseline(old, ids: jobs.map(\.id), now: now)
                baseline = r.baseline; arrivals = r.newIDs
            }
            var logs: [String: Date] = [:]
            let home = collector.home
            for j in jobs {
                // 보호 폴더 안의 로그는 건드리지 않는다(접근 허용 창이 뜰 수 있다)
                let paths = [j.stdoutPath, j.stderrPath].map { p in p.flatMap { Job.touchesProtectedFolder($0, home: home) ? nil : $0 } }
                if let d = lastLogChange(paths) { logs[j.id] = d }
            }
            let result = Collected(jobs: jobs, cache: cache, summaries: summarize(history?.records ?? []),
                                   baseline: baseline, arrivals: arrivals, logChanged: logs,
                                   procs: wantProcs ? collector.collectProcesses() : nil)
            await MainActor.run { self.apply(result, now: now) }
        }
    }

    private func apply(_ r: Collected, now: Date) {
        cache = r.cache
        // 달라진 것만 바꿔 넣는다(표를 통째로 다시 그리지 않게)
        if jobs != r.jobs { jobs = r.jobs }
        if summaries != r.summaries { summaries = r.summaries }
        if logChanged != r.logChanged { logChanged = r.logChanged }
        if let p = r.procs, p != procs { procs = p }
        if baseline != r.baseline, let b = r.baseline, let url = baselineURL { saveBaseline(b, to: url) }
        baseline = r.baseline
        let fresh = Set(r.jobs.map(\.id).filter { r.baseline?.isNew($0, now: now) ?? false })
        if fresh != newIDs { newIDs = fresh }
        // 목록에서 사라진 작업의 확인 표시는 지운다
        let prefixes = r.jobs.map { $0.id + "|" }
        let kept = acknowledged.filter { key in prefixes.contains { key.hasPrefix($0) } }
        if kept != acknowledged { acknowledged = kept; saveAcknowledged() }
        updated = now
        loading = false
        if pending { pending = false; refresh() }
        if !r.arrivals.isEmpty {
            let ids = Set(r.arrivals)
            onArrivals?(r.jobs.filter { ids.contains($0.id) })
        }
    }

    /// 이 실패는 봤다고 표시한다. 다시 돌아 또 실패하면 새로 센다.
    func acknowledge(_ job: Job) {
        // 같은 작업의 지난 확인 표시는 지우고 지금 것만 둔다
        acknowledged = acknowledged.filter { !$0.hasPrefix(job.id + "|") }
        acknowledged.insert(job.failureKey)
        saveAcknowledged()
    }

    private func saveAcknowledged() {
        guard !demo else { return }
        UserDefaults.standard.set(Array(acknowledged).sorted(), forKey: Store.ackKey)
    }

    /// 수집 비용을 잰다(`--probe`). 화면 없이 두 번 수집해 띄운 프로세스 수와 걸린 시간을 적는다.
    nonisolated static func probe() {
        let runner = ProcessRunner()
        let collector = Collector(runner: runner, home: NSHomeDirectory(), uid: Int(getuid()))
        var cache = DetailCache()
        var jobs: [Job] = []
        for round in ["처음", "두 번째"] {
            let before = runner.spawnCount, t = Date()
            jobs = collector.collectJobs(now: Date(), cache: &cache)
            print("\(round) 수집: 프로세스 \(runner.spawnCount - before)개, \(String(format: "%.3f", Date().timeIntervalSince(t)))초, 작업 \(jobs.count)개")
        }
        // 라벨은 찍지 않는다. 개수만.
        for s in Source.allCases { print("  \(s.rawValue): \(jobs.filter { $0.source == s }.count)") }
        print("  설정 파일을 읽을 수 없음: \(jobs.filter { !$0.plistReadable }.count)")
        print("  설정 파일 없이 등록됨: \(jobs.filter { $0.plistPath == nil }.count)")
        var byStatus: [String: Int] = [:]
        for j in jobs {
            let name: String
            switch j.status {
            case .running: name = "실행 중"
            case .notLoaded: name = "꺼짐(미등록)"
            case .disabled: name = "꺼 둠"
            case .neverRan: name = "아직 돈 적 없음"
            case .succeeded: name = "정상"
            case .interrupted: name = "중단됨"
            case .failed: name = "실패"
            case .idle: name = "대기(기록 없음)"
            }
            byStatus[name, default: 0] += 1
        }
        for (k, v) in byStatus.sorted(by: { $0.key < $1.key }) { print("  상태 \(k): \(v)") }
        print("  배지에 셀 실패(내 에이전트): \(jobs.filter { $0.needsAttention(acknowledged: []) }.count)")
        print("  출처를 찾은 것: \(jobs.filter { $0.owner != .unknown }.count)")
    }
}
