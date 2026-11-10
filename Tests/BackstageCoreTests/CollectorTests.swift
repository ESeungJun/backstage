import XCTest
@testable import BackstageCore

final class JobStatusTests: XCTestCase {
    func job(_ kind: Kind = .scheduled, source: Source = .userAgent, loaded: Bool = true, pid: Int? = nil,
             exit: Int? = nil, runs: Int? = nil, neverExited: Bool = false, disabled: Bool = false) -> Job {
        var j = Job(id: "gui/com.example.x", label: "com.example.x", source: source, domain: source == .daemon ? .system : .gui, kind: kind)
        j.loaded = loaded; j.pid = pid; j.lastExit = exit; j.runs = runs; j.neverExited = neverExited; j.disabled = disabled
        return j
    }

    func testNeverRanIsNotSuccess() {
        // launchctl 목록은 한 번도 안 돈 작업도 종료 코드 0 으로 보여 준다
        XCTAssertEqual(job(exit: 0, runs: 0, neverExited: true).status, .neverRan)
        XCTAssertEqual(job(exit: 0, runs: 0).status, .neverRan)
        XCTAssertEqual(statusDescription(.neverRan), "아직 돈 적 없음")
    }

    func testSucceededNeedsRunCount() {
        XCTAssertEqual(job(exit: 0, runs: 686).status, .succeeded(runs: 686))
        XCTAssertEqual(statusDescription(.succeeded(runs: 686)), "정상 · 686회 실행")
        // 실행 횟수를 못 읽었으면 0 을 "정상"이라고 하지 않는다
        XCTAssertEqual(job(exit: 0, runs: nil).status, .idle)
    }

    func testRunningFailedInterrupted() {
        XCTAssertEqual(job(pid: 42, exit: 0, runs: 3).status, .running(pid: 42))
        XCTAssertEqual(job(exit: 126, runs: 12).status, .failed(code: 126, runs: 12))
        XCTAssertEqual(statusDescription(.failed(code: 1, runs: 12)), "오류(1) · 12회 실행")
        XCTAssertEqual(job(exit: -15, runs: 2).status, .interrupted(code: -15))
        XCTAssertEqual(job(exit: -9, runs: 2).status, .interrupted(code: -9))
        XCTAssertEqual(job(exit: -11, runs: 2).status, .failed(code: -11, runs: 2))
    }

    func testNotLoadedAndDisabled() {
        XCTAssertEqual(job(loaded: false).status, .notLoaded)
        XCTAssertEqual(job(loaded: false, disabled: true).status, .disabled)
    }

    func testFailedExcludesInterruptsAndRevivedResidents() {
        XCTAssertTrue(job(exit: 1).failed)
        XCTAssertFalse(job(exit: 0).failed)
        XCTAssertFalse(job(exit: nil).failed)
        XCTAssertFalse(job(exit: -15).failed)
        XCTAssertFalse(job(exit: -9).failed)
        XCTAssertFalse(job(.resident, pid: 9, exit: 1).failed)
        XCTAssertTrue(job(.resident, exit: 1).failed)
    }

    func testAttentionCountsOnlyMyUnacknowledgedFailures() {
        let mine = job(exit: 1, runs: 12)
        XCTAssertTrue(mine.needsAttention(acknowledged: []))
        XCTAssertFalse(mine.needsAttention(acknowledged: [mine.failureKey]))
        // 남의 데몬이 실패한 것은 배지에 세지 않는다
        XCTAssertFalse(job(source: .daemon, exit: 1).needsAttention(acknowledged: []))
        XCTAssertFalse(job(source: .appEmbedded, exit: 1).needsAttention(acknowledged: []))
        // 확인한 뒤 다시 돌아 또 실패하면 새 실패다
        let again = job(exit: 1, runs: 13)
        XCTAssertNotEqual(again.failureKey, mine.failureKey)
        XCTAssertTrue(again.needsAttention(acknowledged: [mine.failureKey]))
        XCTAssertTrue(job(exit: 2, runs: 12).needsAttention(acknowledged: [mine.failureKey]))
    }

    func testProtectedPaths() {
        let home = Fixture.home
        var j = job()
        j.args = ["/bin/bash", "\(home)/Desktop/scripts/backup.sh"]
        XCTAssertEqual(j.protectedPaths(home: home), ["\(home)/Desktop/scripts/backup.sh"])
        j.args = ["/bin/sh", "-c", "cd \(home)/Documents/notes && exec node server.js"]
        XCTAssertEqual(j.protectedPaths(home: home).count, 1)
        j.args = ["/bin/bash", "\(home)/Projects/run.sh"]
        XCTAssertTrue(j.protectedPaths(home: home).isEmpty)
        j.workingDir = "/Volumes/Backup/work"
        XCTAssertEqual(j.protectedPaths(home: home), ["/Volumes/Backup/work"])
        // NFD 로 저장된 한글 경로
        j.workingDir = nil
        j.args = ["\(home)/Desktop/\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}/run.sh"]
        XCTAssertEqual(j.protectedPaths(home: home).count, 1)
        // 데몬은 표시 대상이 아니다
        var d = job(source: .daemon)
        d.args = ["\(home)/Desktop/x"]
        XCTAssertTrue(d.riskyPaths(home: home).isEmpty)
    }

    func testDisplayProgramAndInspectCommand() {
        var j = job()
        j.args = ["/bin/bash", "/Users/you/Projects/daily/run_daily.sh"]
        XCTAssertEqual(j.displayProgram, "run_daily.sh")
        j.args = ["/bin/sh", "-c", "exec /opt/homebrew/bin/caddy run"]
        XCTAssertEqual(j.displayProgram, "caddy")
        j.args = ["/opt/homebrew/bin/caddy", "run"]
        XCTAssertEqual(j.displayProgram, "caddy")
        j.args = []
        XCTAssertEqual(j.displayProgram, "-")
        XCTAssertEqual(j.inspectCommand(uid: 501), "launchctl print gui/501/com.example.x")
        XCTAssertEqual(job(source: .daemon).inspectCommand(uid: 501), "launchctl print system/com.example.x")
        // 라벨에 셸이 해석할 글자가 있으면 따옴표로 감싼다
        let odd = Job(id: "gui/x", label: "a; rm -rf ~", source: .userAgent, domain: .gui)
        XCTAssertEqual(odd.inspectCommand(uid: 501), "launchctl print 'gui/501/a; rm -rf ~'")
        let quote = Job(id: "gui/y", label: "it's", source: .userAgent, domain: .gui)
        XCTAssertEqual(quote.inspectCommand(uid: 501), #"launchctl print 'gui/501/it'\''s'"#)
    }

    func testExitDescription() {
        XCTAssertEqual(exitDescription(0), "정상")
        XCTAssertEqual(exitDescription(126), "실행 불가(126) · 파일 접근 권한 문제일 수 있음")
        XCTAssertEqual(exitDescription(-11), "신호로 종료(-11)")
        XCTAssertEqual(exitDescription(3), "오류(3)")
    }
}

final class CollectorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    let userDir = "/Users/you/Library/LaunchAgents"
    let embeddedPlist = "/Applications/Example Suite.app/Contents/Library/LaunchAgents/com.example.embedded.agent.plist"

    func makeFiles() -> FakeFiles {
        var f = FakeFiles()
        f.dirs[userDir] = ["com.example.photo-backup.plist", "com.example.notes-server.plist", "com.example.fresh.plist",
                           "com.example.broken-backup.plist", "com.example.switched-off.plist", "notes.txt"]
        f.dirs["/Library/LaunchAgents"] = ["com.vendor.shared-agent.plist"]
        f.dirs["/Library/LaunchDaemons"] = ["com.vendor.netd.plist", "com.vendor.locked.plist", "com.vendor.daemon-file.plist"]
        f.data["\(userDir)/com.example.photo-backup.plist"] = Fixture.plist([
            "Label": "com.example.photo-backup", "ProgramArguments": ["/bin/bash", "/Users/you/Projects/backup/run.sh"],
            "StartCalendarInterval": ["Hour": 2, "Minute": 30]])
        f.data["\(userDir)/com.example.notes-server.plist"] = Fixture.plist([
            "Label": "com.example.notes-server", "ProgramArguments": ["/usr/local/bin/node", "/Users/you/Projects/notes/server.js"],
            "KeepAlive": true])
        f.data["\(userDir)/com.example.fresh.plist"] = Fixture.plist([
            "Label": "com.example.fresh", "ProgramArguments": ["/Users/you/bin/fresh"], "StartInterval": 3600])
        f.data["\(userDir)/com.example.broken-backup.plist"] = Fixture.plist([
            "Label": "com.example.broken-backup", "ProgramArguments": ["/bin/bash", "/Users/you/Desktop/old/backup.sh"],
            "StartCalendarInterval": ["Hour": 4, "Minute": 0]])
        f.data["\(userDir)/com.example.switched-off.plist"] = Fixture.plist([
            "Label": "com.example.switched-off", "ProgramArguments": ["/Users/you/bin/off"], "RunAtLoad": true])
        f.data["/Library/LaunchAgents/com.vendor.shared-agent.plist"] = Fixture.plist([
            "Label": "com.vendor.shared-agent", "ProgramArguments": ["/Applications/Gone.app/Contents/MacOS/agent"], "RunAtLoad": true])
        f.data["/Library/LaunchDaemons/com.vendor.netd.plist"] = Fixture.plist([
            "Label": "com.vendor.netd", "ProgramArguments": ["/Library/PrivilegedHelperTools/com.vendor.netd"],
            "MachServices": ["com.vendor.netd": true]])
        // com.vendor.locked.plist, com.vendor.daemon-file.plist: 관리자 전용이라 내용을 읽지 못한다
        f.present = ["/Library/LaunchDaemons/com.vendor.locked.plist", "/Library/LaunchDaemons/com.vendor.daemon-file.plist",
                     "/Applications/Example Suite.app"]
        f.data[embeddedPlist] = Fixture.plist([
            "Label": "com.example.embedded.agent",
            "ProgramArguments": ["/Applications/Example Suite.app/Contents/MacOS/agent", "--background"],
            "KeepAlive": true, "AssociatedBundleIdentifiers": "com.example.suite"])
        return f
    }

    func makeRunner() -> FakeRunner {
        let r = FakeRunner()
        r.outputs["print gui/501"] = Fixture.guiDomain
        r.outputs["print system"] = Fixture.systemDomain
        r.outputs["print gui/501/com.example.photo-backup"] = Fixture.scheduledService
        r.outputs["print gui/501/com.example.fresh"] = Fixture.neverRanService
        r.outputs["print gui/501/com.example.notes-server"] = Fixture.runningService
        r.outputs["print gui/501/com.example.loginitem"] = Fixture.smAppService
        r.outputs["print gui/501/com.example.embedded.agent"] = Fixture.embeddedService
        r.outputs["print gui/501/com.example.updater.helper"] = Fixture.submittedService
        r.outputs["print system/com.vendor.realname"] = Fixture.signalledService
        r.outputs["print system/org.example.printd"] = Fixture.builtinService
        r.outputs["print system/com.vendor.task.temp"] = Fixture.tempPlistService
        return r
    }

    func collect(_ runner: FakeRunner, cache: inout DetailCache) -> [String: Job] {
        let c = Collector(runner: runner, files: makeFiles(), home: Fixture.home, uid: Fixture.uid)
        let jobs = c.collectJobs(now: now, cache: &cache)
        XCTAssertEqual(Set(jobs.map(\.id)).count, jobs.count, "ID 가 겹친다")
        return Dictionary(uniqueKeysWithValues: jobs.map { ($0.label, $0) })
    }

    func testPlistJobsGetStatusFromDomainPrint() {
        var cache = DetailCache()
        let jobs = collect(makeRunner(), cache: &cache)
        XCTAssertEqual(jobs["com.example.photo-backup"]?.status, .succeeded(runs: 686))
        XCTAssertEqual(jobs["com.example.photo-backup"]?.schedule, "매일 02:30")
        XCTAssertEqual(jobs["com.example.notes-server"]?.status, .running(pid: 4821))
        XCTAssertEqual(jobs["com.example.fresh"]?.status, .neverRan)
        // 상세를 못 읽어도 목록의 종료 코드로 실패를 안다
        XCTAssertEqual(jobs["com.example.broken-backup"]?.status, .failed(code: 126, runs: nil))
        XCTAssertEqual(jobs["com.example.switched-off"]?.status, .disabled)
        XCTAssertEqual(jobs["com.vendor.netd"]?.status, .running(pid: 334))
        XCTAssertNil(jobs["notes"])
    }

    func testEmbeddedAndSubmittedServicesAreListed() {
        var cache = DetailCache()
        let jobs = collect(makeRunner(), cache: &cache)
        // 앱 번들 안 plist: 그 파일에서 일정을 읽는다
        let embedded = jobs["com.example.embedded.agent"]
        XCTAssertEqual(embedded?.source, .appEmbedded)
        XCTAssertEqual(embedded?.plistPath, embeddedPlist)
        XCTAssertEqual(embedded?.kind, .resident)
        XCTAssertEqual(embedded?.owner, .bundleID("com.example.suite"))
        // SMAppService: 설정 파일 없이 부모 번들만 안다
        let login = jobs["com.example.loginitem"]
        XCTAssertEqual(login?.source, .appEmbedded)
        XCTAssertNil(login?.plistPath)
        XCTAssertEqual(login?.owner, .bundleID("com.example.mainapp"))
        XCTAssertEqual(login?.origin, "앱이 로그인 항목·도우미로 등록(smd)")
        XCTAssertEqual(login?.args, ["Contents/Library/LoginItems/ExampleHelper.app"])
        XCTAssertEqual(login?.status, .succeeded(runs: 1))
        // 프로그램이 직접 올린 것
        let helper = jobs["com.example.updater.helper"]
        XCTAssertEqual(helper?.origin, "프로그램이 실행 중에 직접 등록(ExampleUpdater)")
        XCTAssertEqual(helper?.stdoutPath, "/Users/you/Library/Logs/ExampleUpdater/helper.log")
        XCTAssertEqual(helper?.status, .running(pid: 7001))
        // Apple 서비스와 일반 앱 실행은 넣지 않는다
        XCTAssertFalse(jobs.keys.contains { $0.hasPrefix("com.apple.") || $0.hasPrefix("application.") })
    }

    func testUnreadablePlistIsShownNotDropped() {
        var cache = DetailCache()
        let jobs = collect(makeRunner(), cache: &cache)
        let locked = jobs["com.vendor.locked"]
        XCTAssertEqual(locked?.plistReadable, false)
        XCTAssertEqual(locked?.source, .daemon)
        XCTAssertEqual(locked?.schedule, "설정 파일을 읽을 수 없음(관리자 전용)")
        XCTAssertEqual(locked?.status, .failed(code: 1, runs: nil))
    }

    func testUnreadablePlistWithDifferentLabelIsMerged() {
        // 파일 이름은 daemon-file 인데 실제 라벨은 realname. 두 줄로 나오면 안 된다.
        var cache = DetailCache()
        let jobs = collect(makeRunner(), cache: &cache)
        XCTAssertNil(jobs["com.vendor.daemon-file"])
        let real = jobs["com.vendor.realname"]
        XCTAssertEqual(real?.source, .daemon)
        XCTAssertEqual(real?.plistPath, "/Library/LaunchDaemons/com.vendor.daemon-file.plist")
        XCTAssertEqual(real?.plistReadable, false)
        XCTAssertEqual(real?.args, ["/Library/Vendor/bin/realnamed"])
        XCTAssertEqual(real?.status, .running(pid: 412))
        XCTAssertEqual(real?.lastExit, -11)
    }

    func testBuiltinServicesUnderSystemAreExcluded() {
        var cache = DetailCache()
        XCTAssertNil(collect(makeRunner(), cache: &cache)["org.example.printd"])
        // 한 번 가려낸 뒤로는 다시 묻지 않는다
        let again = makeRunner()
        XCTAssertNil(collect(again, cache: &cache)["org.example.printd"])
        XCTAssertFalse(again.calls.contains("print system/org.example.printd"))
    }

    func testDeletedTempPlistIsNotShownAsLocked() {
        var cache = DetailCache()
        let temp = collect(makeRunner(), cache: &cache)["com.vendor.task.temp"]
        XCTAssertNil(temp?.plistPath)
        XCTAssertEqual(temp?.plistReadable, true)
        XCTAssertEqual(temp?.origin, "임시 설정 파일로 등록됨(지금은 파일 없음)")
        XCTAssertEqual(temp?.args, ["/Library/Vendor/bin/task"])
    }

    func testOwnerGuess() {
        var cache = DetailCache()
        let jobs = collect(makeRunner(), cache: &cache)
        XCTAssertEqual(jobs["com.example.photo-backup"]?.owner, .selfMade)
        XCTAssertEqual(jobs["com.vendor.shared-agent"]?.owner, .app(path: "/Applications/Gone.app"))
        XCTAssertEqual(jobs["com.vendor.shared-agent"]?.ownerMissing, true)
        XCTAssertEqual(jobs["com.vendor.netd"]?.owner, .unknown)
    }

    func testSecondRefreshSkipsDetailForStillRunningServices() {
        var cache = DetailCache()
        let first = makeRunner()
        _ = collect(first, cache: &cache)
        XCTAssertEqual(first.calls.filter { $0 == "print gui/501" || $0 == "print system" }.count, 2)
        XCTAssertTrue(first.calls.contains("print gui/501/com.example.notes-server"))

        let second = makeRunner()
        let jobs = collect(second, cache: &cache)
        // 같은 PID 로 돌고 있는 것은 다시 묻지 않는다
        XCTAssertFalse(second.calls.contains("print gui/501/com.example.notes-server"))
        XCTAssertFalse(second.calls.contains("print gui/501/com.example.embedded.agent"))
        // 쉬고 있는 것은 그 사이에 돌았을 수 있으니 다시 읽는다
        XCTAssertTrue(second.calls.contains("print gui/501/com.example.photo-backup"))
        XCTAssertLessThan(second.calls.count, first.calls.count)
        XCTAssertEqual(jobs["com.example.notes-server"]?.runs, 1)
        XCTAssertEqual(jobs["com.example.embedded.agent"]?.kind, .resident)
    }

    func testLaunchctlFailureStillListsPlists() {
        var cache = DetailCache()
        let jobs = collect(FakeRunner(), cache: &cache)   // 모든 명령이 실패
        XCTAssertEqual(jobs["com.example.photo-backup"]?.status, .notLoaded)
        XCTAssertFalse(cache.domainRead)
        XCTAssertNotNil(jobs["com.vendor.locked"])
        XCTAssertNil(jobs["com.example.loginitem"])
    }
}

final class TailTests: XCTestCase {
    func testTailDropsPartialFirstLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backstage-tail-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("첫 줄은 잘려 나간다\n둘째 줄\n셋째 줄\n".utf8).write(to: url)
        // 한글 글자 중간에서 자르는 길이
        XCTAssertEqual(tail(url.path, bytes: 25), "둘째 줄\n셋째 줄\n")
        XCTAssertEqual(tail(url.path, bytes: 4000), "첫 줄은 잘려 나간다\n둘째 줄\n셋째 줄\n")
        XCTAssertEqual(tail("/no/such/file"), "")
        XCTAssertEqual(tail("/dev/zero"), "")   // 장치 파일은 읽지 않는다
        XCTAssertEqual(tail(nil), "")
    }
}
