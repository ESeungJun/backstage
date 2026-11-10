import Foundation

// 실행 기록부. launchd 는 "언제 마지막으로 돌았나"를 알려 주지 않으므로,
// 갱신할 때마다 실행 횟수·PID 를 지난번과 비교해 Backstage 가 직접 본 실행을 적어 둔다.
// 시각은 실제 실행 시각이 아니라 "끝난 것을 알아챈 시각"이다.

/// 비교에 쓰는 서비스 한 개의 지난 모습.
public struct RunSnapshot: Codable, Hashable, Sendable {
    public var runs: Int?
    public var pid: Int?
    public init(runs: Int?, pid: Int?) { self.runs = runs; self.pid = pid }
}

/// 기록부 한 줄.
public struct RunRecord: Codable, Hashable, Sendable {
    public var id: String      // 작업 ID
    public var at: Date        // 알아챈 시각
    public var since: Date?    // 그 전에 마지막으로 살펴본 시각. 실제 실행은 since~at 사이다
    public var exit: Int?      // 마지막 실행의 종료 코드. nil = 읽지 못함
    public var count: Int      // 이 사이에 끝난 실행 수(2 이상이면 앞의 것들은 결과를 모른다)
    public init(id: String, at: Date, since: Date? = nil, exit: Int?, count: Int) {
        self.id = id; self.at = at; self.since = since; self.exit = exit; self.count = count
    }
}

/// 지난 모습과 지금을 비교해 그 사이에 끝난 실행 수를 센다.
public func completedRuns(prev: RunSnapshot?, now: RunSnapshot) -> Int {
    guard let prev else { return 0 }   // 처음 본 서비스는 기준만 잡는다
    guard let nowRuns = now.runs, let prevRuns = prev.runs else {
        // 실행 횟수를 못 읽으면 PID 가 사라지거나 바뀐 것만 센다
        if let p = prev.pid, p != now.pid { return 1 }
        return 0
    }
    // launchd 는 실행을 시작할 때 횟수를 올린다. 재시동·재등록으로 횟수가 줄었으면 0 에서 다시 센 것이다.
    let reset = nowRuns < prevRuns
    let started = reset ? nowRuns : nowRuns - prevRuns
    let wasRunning = (!reset && prev.pid != nil) ? 1 : 0
    return max(0, started + wasRunning - (now.pid != nil ? 1 : 0))
}

/// 작업 하나의 기록 요약.
public struct RunSummary: Hashable, Sendable {
    public var lastAt: Date?
    public var lastSince: Date?
    public var lastExit: Int?
    public var succeeded = 0
    public var failed = 0
    public var recent: [Int?] = []   // 최근 것이 뒤. 종료 코드, nil = 결과 모름
    public init() {}

    public var judged: Int { succeeded + failed }
    /// 성공률(%). 결과를 아는 실행이 없으면 nil.
    public var successRate: Int? { judged == 0 ? nil : Int((Double(succeeded) / Double(judged) * 100).rounded()) }
}

public func summarize(_ records: [RunRecord], recentLimit: Int = 14) -> [String: RunSummary] {
    var out: [String: RunSummary] = [:]
    for r in records.sorted(by: { $0.at < $1.at }) {
        var s = out[r.id] ?? RunSummary()
        s.lastAt = r.at; s.lastSince = r.since; s.lastExit = r.exit
        if r.count > 1 { s.recent.append(contentsOf: Array(repeating: nil, count: min(r.count - 1, recentLimit))) }
        s.recent.append(r.exit)
        if let e = r.exit {
            if e == 0 { s.succeeded += 1 } else if !Job.isInterrupt(e) { s.failed += 1 }
        }
        if s.recent.count > recentLimit { s.recent.removeFirst(s.recent.count - recentLimit) }
        out[r.id] = s
    }
    return out
}

/// 기록부 파일. `history.jsonl`(한 줄에 실행 하나)과 `snapshot.json`(지난 모습).
public final class HistoryStore: @unchecked Sendable {
    public let dir: URL
    public let maxLines: Int
    private var snapshots: [String: RunSnapshot] = [:]
    private var observedAt: Date?

    struct SnapshotFile: Codable {
        var at: Date
        var items: [String: RunSnapshot]
    }
    public private(set) var records: [RunRecord] = []
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    var historyURL: URL { dir.appendingPathComponent("history.jsonl") }
    var snapshotURL: URL { dir.appendingPathComponent("snapshot.json") }

    public init(dir: URL, maxLines: Int = 4000) {
        self.dir = dir; self.maxLines = maxLines
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    /// 파일을 읽는다. 깨진 줄(쓰다 끊긴 마지막 줄 등)은 건너뛰고 나머지는 살린다.
    func load() {
        if let text = try? String(contentsOf: historyURL, encoding: .utf8) {
            records = text.split(separator: "\n").compactMap { try? decoder.decode(RunRecord.self, from: Data($0.utf8)) }
        }
        if let data = try? Data(contentsOf: snapshotURL),
           let s = try? decoder.decode(SnapshotFile.self, from: data) { snapshots = s.items; observedAt = s.at }
    }

    /// 지금 상태를 지난 모습과 비교해 새로 끝난 실행을 기록한다. 새로 적은 줄을 돌려준다.
    @discardableResult
    public func observe(_ jobs: [Job], now: Date) -> [RunRecord] {
        var added: [RunRecord] = []
        var next: [String: RunSnapshot] = [:]
        for j in jobs where j.loaded {
            let snap = RunSnapshot(runs: j.runs, pid: j.pid)
            next[j.id] = snap
            let n = completedRuns(prev: snapshots[j.id], now: snap)
            if n > 0 { added.append(RunRecord(id: j.id, at: now, since: observedAt, exit: j.lastExit, count: n)) }
        }
        snapshots = next
        observedAt = now
        if !added.isEmpty { append(added) }
        if let data = try? encoder.encode(SnapshotFile(at: now, items: next)) { try? data.write(to: snapshotURL, options: .atomic) }
        return added
    }

    private func append(_ new: [RunRecord]) {
        records.append(contentsOf: new)
        if records.count > maxLines {
            // 너무 길어지면 최근 절반만 남겨 통째로 다시 쓴다(임시 파일에 쓰고 바꿔치기).
            records.removeFirst(records.count - maxLines / 2)
            try? Data(lines(records).utf8).write(to: historyURL, options: .atomic)
            return
        }
        let text = lines(new)
        if let fh = try? FileHandle(forWritingTo: historyURL) {
            defer { try? fh.close() }
            let end = (try? fh.seekToEnd()) ?? 0
            // 앞선 쓰기가 줄 중간에서 끊겼으면 줄을 바꾸고 이어 쓴다(다음 줄까지 깨지지 않게)
            if end > 0 {
                try? fh.seek(toOffset: end - 1)
                if (try? fh.read(upToCount: 1)) != Data([0x0A]) { try? fh.write(contentsOf: Data([0x0A])) }
            }
            try? fh.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: historyURL, options: .atomic)
        }
    }

    private func lines(_ rs: [RunRecord]) -> String {
        rs.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) + "\n" }.joined()
    }
}

// MARK: - 기준선 (새로 들어온 항목)

public struct Baseline: Codable, Hashable, Sendable {
    public var established: Date            // 처음 목록을 본 때. 이때 있던 것은 "새 항목"이 아니다
    public var firstSeen: [String: Date]
    public init(established: Date, firstSeen: [String: Date]) {
        self.established = established; self.firstSeen = firstSeen
    }

    /// 기준선 이후에 생겼고, 아직 며칠 지나지 않은 항목인지.
    public func isNew(_ id: String, now: Date, days: Int = 7) -> Bool {
        guard let seen = firstSeen[id], seen > established else { return false }
        return now.timeIntervalSince(seen) < Double(days) * 86400
    }
}

/// 지금 목록을 기준선과 비교한다. 처음이면 전부 기준선으로 삼고 새 항목은 없다고 본다.
public func updateBaseline(_ old: Baseline?, ids: [String], now: Date) -> (baseline: Baseline, newIDs: [String]) {
    guard var b = old else {
        return (Baseline(established: now, firstSeen: Dictionary(ids.map { ($0, now) }, uniquingKeysWith: { a, _ in a })), [])
    }
    var fresh: [String] = []
    for id in ids where b.firstSeen[id] == nil {
        b.firstSeen[id] = now
        fresh.append(id)
    }
    // 지금 없고 처음 본 지 30일이 넘은 항목은 지운다(임시 서비스가 쌓이지 않게).
    let present = Set(ids)
    b.firstSeen = b.firstSeen.filter { present.contains($0.key) || now.timeIntervalSince($0.value) < 30 * 86400 }
    return (b, fresh)
}

public func loadBaseline(_ url: URL) -> Baseline? {
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    return (try? Data(contentsOf: url)).flatMap { try? d.decode(Baseline.self, from: $0) }
}

public func saveBaseline(_ b: Baseline, to url: URL) {
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys
    if let data = try? e.encode(b) { try? data.write(to: url, options: .atomic) }
}
