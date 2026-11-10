import XCTest
@testable import BackstageCore

final class CompletedRunsTests: XCTestCase {
    func snap(_ runs: Int?, _ pid: Int? = nil) -> RunSnapshot { RunSnapshot(runs: runs, pid: pid) }

    func testFirstSightIsBaselineOnly() {
        XCTAssertEqual(completedRuns(prev: nil, now: snap(686)), 0)
    }

    func testNothingChanged() {
        XCTAssertEqual(completedRuns(prev: snap(5), now: snap(5)), 0)
        XCTAssertEqual(completedRuns(prev: snap(1, 40), now: snap(1, 40)), 0)
    }

    func testRanAndFinishedBetweenChecks() {
        XCTAssertEqual(completedRuns(prev: snap(5), now: snap(6)), 1)
        XCTAssertEqual(completedRuns(prev: snap(5), now: snap(8)), 3)
    }

    func testStartedButStillRunningIsNotCompleted() {
        XCTAssertEqual(completedRuns(prev: snap(5), now: snap(6, 77)), 0)
    }

    func testRunningOneFinished() {
        XCTAssertEqual(completedRuns(prev: snap(6, 77), now: snap(6)), 1)
        // 죽고 다시 떴다: 앞의 것 하나가 끝났다
        XCTAssertEqual(completedRuns(prev: snap(6, 77), now: snap(7, 80)), 1)
    }

    func testCounterResetAfterReboot() {
        XCTAssertEqual(completedRuns(prev: snap(686), now: snap(1)), 1)
        XCTAssertEqual(completedRuns(prev: snap(686, 77), now: snap(1, 90)), 0)
        XCTAssertEqual(completedRuns(prev: snap(686), now: snap(0)), 0)
    }

    func testWithoutRunCountFallsBackToPID() {
        XCTAssertEqual(completedRuns(prev: snap(nil, 77), now: snap(nil)), 1)
        XCTAssertEqual(completedRuns(prev: snap(nil, 77), now: snap(nil, 78)), 1)
        XCTAssertEqual(completedRuns(prev: snap(nil), now: snap(nil)), 0)
        XCTAssertEqual(completedRuns(prev: snap(nil), now: snap(nil, 5)), 0)
    }
}

final class HistoryStoreTests: XCTestCase {
    var dir: URL!
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("backstage-history-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func job(_ label: String, runs: Int?, pid: Int? = nil, exit: Int? = 0, loaded: Bool = true) -> Job {
        var j = Job(id: "gui/\(label)", label: label, source: .userAgent, domain: .gui, kind: .scheduled)
        j.loaded = loaded; j.runs = runs; j.pid = pid; j.lastExit = exit
        return j
    }

    func testObserveRecordsOnlyNewCompletions() {
        let store = HistoryStore(dir: dir)
        XCTAssertTrue(store.observe([job("a", runs: 10), job("b", runs: 1, pid: 5, exit: nil)], now: t0).isEmpty)
        let added = store.observe([job("a", runs: 11, exit: 1), job("b", runs: 1, pid: 5, exit: nil)], now: t0 + 300)
        XCTAssertEqual(added, [RunRecord(id: "gui/a", at: t0 + 300, since: t0, exit: 1, count: 1)])
        XCTAssertTrue(store.observe([job("a", runs: 11, exit: 1), job("b", runs: 1, pid: 5, exit: nil)], now: t0 + 600).isEmpty)
    }

    func testSurvivesRestart() {
        let first = HistoryStore(dir: dir)
        first.observe([job("a", runs: 10)], now: t0)
        first.observe([job("a", runs: 11)], now: t0 + 300)

        let second = HistoryStore(dir: dir)   // 앱을 다시 켠 것
        XCTAssertEqual(second.records.count, 1)
        // 꺼져 있던 사이에 세 번 돌았다: 한 줄로, 구간과 함께 적는다
        let added = second.observe([job("a", runs: 14, exit: 2)], now: t0 + 9000)
        XCTAssertEqual(added, [RunRecord(id: "gui/a", at: t0 + 9000, since: t0 + 300, exit: 2, count: 3)])
        XCTAssertEqual(HistoryStore(dir: dir).records.count, 2)
    }

    func testCorruptLinesAreSkippedAndAppendingStillWorks() throws {
        let store = HistoryStore(dir: dir)
        store.observe([job("a", runs: 1)], now: t0)
        store.observe([job("a", runs: 2)], now: t0 + 60)
        // 쓰다가 끊긴 줄(줄바꿈 없이 끝남)과 쓰레기 줄
        let url = dir.appendingPathComponent("history.jsonl")
        let fh = try FileHandle(forWritingTo: url)
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("이건 JSON 이 아니다\n{\"id\":\"gui/a\",\"at\":\"2026-11".utf8))
        try fh.close()

        let reopened = HistoryStore(dir: dir)
        XCTAssertEqual(reopened.records.count, 1)
        reopened.observe([job("a", runs: 3)], now: t0 + 120)
        // 끊긴 줄 뒤에 붙은 새 줄이 깨지지 않아야 한다
        XCTAssertEqual(HistoryStore(dir: dir).records.count, 2)
    }

    func testCorruptSnapshotStartsFreshWithoutLosingHistory() throws {
        let store = HistoryStore(dir: dir)
        store.observe([job("a", runs: 1)], now: t0)
        store.observe([job("a", runs: 2)], now: t0 + 60)
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("snapshot.json"))

        let reopened = HistoryStore(dir: dir)
        XCTAssertEqual(reopened.records.count, 1)
        // 지난 모습을 잃었으니 기준만 다시 잡는다(가짜 실행을 적지 않는다)
        XCTAssertTrue(reopened.observe([job("a", runs: 9)], now: t0 + 120).isEmpty)
        XCTAssertEqual(reopened.observe([job("a", runs: 10)], now: t0 + 180).count, 1)
    }

    func testTrimKeepsRecentHalf() {
        let store = HistoryStore(dir: dir, maxLines: 10)
        store.observe([job("a", runs: 0)], now: t0)
        for i in 1...11 { store.observe([job("a", runs: i)], now: t0 + Double(i * 60)) }
        XCTAssertEqual(store.records.count, 5)
        XCTAssertEqual(store.records.last?.at, t0 + 660)
        let reopened = HistoryStore(dir: dir, maxLines: 10)
        XCTAssertEqual(reopened.records, store.records)
        // 줄인 뒤에도 이어 쓸 수 있다
        reopened.observe([job("a", runs: 12)], now: t0 + 720)
        XCTAssertEqual(HistoryStore(dir: dir, maxLines: 10).records.count, 6)
    }

    func testUnloadedJobsAreNotTracked() {
        let store = HistoryStore(dir: dir)
        store.observe([job("a", runs: 3)], now: t0)
        store.observe([job("a", runs: nil, loaded: false)], now: t0 + 60)
        // 다시 올라오면 기준부터 다시
        XCTAssertTrue(store.observe([job("a", runs: 1)], now: t0 + 120).isEmpty)
    }

    func testSummarize() {
        let id = "gui/a"
        let recs = [
            RunRecord(id: id, at: t0, exit: 0, count: 1),
            RunRecord(id: id, at: t0 + 60, exit: 1, count: 1),
            RunRecord(id: id, at: t0 + 120, exit: -15, count: 1),   // 중단: 성공도 실패도 아니다
            RunRecord(id: id, at: t0 + 180, since: t0 + 120, exit: 0, count: 3),
            RunRecord(id: "gui/b", at: t0, exit: nil, count: 1),
        ]
        let s = summarize(recs)
        XCTAssertEqual(s[id]?.lastAt, t0 + 180)
        XCTAssertEqual(s[id]?.lastSince, t0 + 120)
        XCTAssertEqual(s[id]?.succeeded, 2)
        XCTAssertEqual(s[id]?.failed, 1)
        XCTAssertEqual(s[id]?.successRate, 67)
        XCTAssertEqual(s[id]?.recent, [0, 1, -15, nil, nil, 0])
        XCTAssertNil(s["gui/b"]?.successRate)
        XCTAssertEqual(summarize(Array(repeating: recs[0], count: 30))[id]?.recent.count, 14)
    }
}

final class BaselineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)
    let day = 86400.0

    func testFirstRunHasNoNewItems() {
        let (b, new) = updateBaseline(nil, ids: ["gui/a", "gui/b"], now: t0)
        XCTAssertTrue(new.isEmpty)
        XCTAssertFalse(b.isNew("gui/a", now: t0 + day))
    }

    func testNewItemIsReportedOnceAndStaysNewForAWeek() {
        let (b0, _) = updateBaseline(nil, ids: ["gui/a"], now: t0)
        let (b1, new1) = updateBaseline(b0, ids: ["gui/a", "gui/c"], now: t0 + day)
        XCTAssertEqual(new1, ["gui/c"])
        let (b2, new2) = updateBaseline(b1, ids: ["gui/a", "gui/c"], now: t0 + 2 * day)
        XCTAssertTrue(new2.isEmpty)
        XCTAssertTrue(b2.isNew("gui/c", now: t0 + 3 * day))
        XCTAssertFalse(b2.isNew("gui/c", now: t0 + 9 * day))
        XCTAssertFalse(b2.isNew("gui/a", now: t0 + 3 * day))
    }

    func testBrieflyMissingItemIsNotNewAgain() {
        let (b0, _) = updateBaseline(nil, ids: ["gui/a"], now: t0)
        let (b1, _) = updateBaseline(b0, ids: [], now: t0 + day)
        let (_, new) = updateBaseline(b1, ids: ["gui/a"], now: t0 + 2 * day)
        XCTAssertTrue(new.isEmpty)
    }

    func testLongGoneItemsArePruned() {
        let (b0, _) = updateBaseline(nil, ids: ["gui/a", "gui/tmp"], now: t0)
        let (b1, _) = updateBaseline(b0, ids: ["gui/a"], now: t0 + 40 * day)
        XCTAssertNil(b1.firstSeen["gui/tmp"])
        XCTAssertNotNil(b1.firstSeen["gui/a"])
    }

    func testSaveLoadAndCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backstage-baseline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (b, _) = updateBaseline(nil, ids: ["gui/a"], now: t0)
        saveBaseline(b, to: url)
        XCTAssertEqual(loadBaseline(url), b)
        try Data("{".utf8).write(to: url)
        XCTAssertNil(loadBaseline(url))
    }
}
