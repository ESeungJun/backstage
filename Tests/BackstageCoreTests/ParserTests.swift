import XCTest
@testable import BackstageCore

final class ScheduleTests: XCTestCase {
    func testDescribeCalendar() {
        XCTAssertEqual(describeCalendar(["Hour": 19, "Minute": 7]), "매일 19:07")
        XCTAssertEqual(describeCalendar(["Weekday": 1, "Hour": 9, "Minute": 10]), "매주 월요일 09:10")
        XCTAssertEqual(describeCalendar(["Weekday": 7, "Hour": 9, "Minute": 0]), "매주 일요일 09:00")
        XCTAssertEqual(describeCalendar(["Day": 1, "Hour": 9, "Minute": 20]), "매월 1일 09:20")
        XCTAssertEqual(describeCalendar(["Month": 3, "Day": 2, "Hour": 0, "Minute": 0]), "매년 3월 2일 00:00")
        XCTAssertEqual(describeCalendar(["Minute": 15]), "매시 15분")
        XCTAssertEqual(describeCalendar([:]), "매분")
    }

    /// Hour 만 있으면 그 시간 내내 매분이다. "매일 03:00"으로 읽으면 60배 틀린다.
    func testHourOnlyIsEveryMinuteOfThatHour() {
        XCTAssertEqual(describeCalendar(["Hour": 3]), "매일 3시대 매분")
        XCTAssertEqual(describeCalendar(["Weekday": 2, "Hour": 3]), "매주 화요일 3시대 매분")
    }

    func testNextCalendarDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
        }
        let now = date(2026, 11, 10, 3, 10, 20)   // 화요일
        XCTAssertEqual(nextCalendarDate(["Hour": 19, "Minute": 7], after: now, calendar: cal), date(2026, 11, 10, 19, 7))
        XCTAssertEqual(nextCalendarDate(["Hour": 2, "Minute": 30], after: now, calendar: cal), date(2026, 11, 11, 2, 30))
        XCTAssertEqual(nextCalendarDate(["Weekday": 1, "Hour": 9, "Minute": 10], after: now, calendar: cal), date(2026, 11, 16, 9, 10))
        // 3시대 매분: 지금이 03:10:20 이면 다음은 03:11
        XCTAssertEqual(nextCalendarDate(["Hour": 3], after: now, calendar: cal), date(2026, 11, 10, 3, 11))
        // 3시대가 지났으면 내일 03:00
        XCTAssertEqual(nextCalendarDate(["Hour": 3], after: date(2026, 11, 10, 4, 0), calendar: cal), date(2026, 11, 11, 3, 0))
        XCTAssertEqual(nextCalendarDate([:], after: now, calendar: cal), date(2026, 11, 10, 3, 11))
        XCTAssertEqual(nextCalendarDate(["Minute": 15], after: now, calendar: cal), date(2026, 11, 10, 3, 15))
    }

    func testDescribeInterval() {
        XCTAssertEqual(describeInterval(1800), "30분마다")
        XCTAssertEqual(describeInterval(3600), "1시간마다")
        XCTAssertEqual(describeInterval(172800), "2일마다")
        XCTAssertEqual(describeInterval(45), "45초마다")
    }
}

final class LaunchctlParserTests: XCTestCase {
    func testDomainPrintReadsServicesBlockOnly() {
        let snap = parseDomainPrint(Fixture.guiDomain)
        XCTAssertEqual(snap.services.count, 12)
        XCTAssertEqual(snap.services["com.example.notes-server"], ServiceRow(label: "com.example.notes-server", pid: 4821, lastExit: nil))
        XCTAssertEqual(snap.services["com.example.photo-backup"], ServiceRow(label: "com.example.photo-backup", pid: nil, lastExit: 0))
        XCTAssertEqual(snap.services["com.example.broken-backup"]?.lastExit, 126)
        XCTAssertEqual(snap.services["com.example.interrupted"]?.lastExit, -15)
        // "(pe)"·"(jt)" 는 종료 코드가 아니다
        XCTAssertEqual(snap.services["com.apple.exampled"], ServiceRow(label: "com.apple.exampled", pid: 67468, lastExit: nil))
        XCTAssertEqual(snap.services["com.example.updater.helper"]?.pid, 7001)
        // 다른 블록(endpoints, unmanaged processes)의 줄은 서비스가 아니다
        XCTAssertNil(snap.services["com.apple.xpc.launchd.unmanaged.example.501"])
    }

    func testDomainPrintReadsDisabledServices() {
        let snap = parseDomainPrint(Fixture.guiDomain)
        XCTAssertEqual(snap.disabled, ["com.example.switched-off"])
    }

    func testSystemDomainIgnoresNestedSubdomainServices() {
        let snap = parseDomainPrint(Fixture.systemDomain)
        XCTAssertEqual(Set(snap.services.keys), ["com.vendor.netd", "com.vendor.locked", "com.apple.exampled", "com.vendor.realname",
                                               "org.example.printd", "com.vendor.task.temp"])
        XCTAssertEqual(snap.services["com.vendor.realname"]?.lastExit, -11)
        XCTAssertEqual(snap.disabled, ["com.vendor.olddaemon"])
    }

    func testEmptyOrFailedOutput() {
        XCTAssertTrue(parseDomainPrint("").services.isEmpty)
        XCTAssertTrue(parseDomainPrint(Fixture.notFound).services.isEmpty)
        XCTAssertNil(parseServicePrint(""))
        XCTAssertNil(parseServicePrint(Fixture.notFound))
    }

    func testServicePrintScheduled() throws {
        let d = try XCTUnwrap(parseServicePrint(Fixture.scheduledService))
        XCTAssertEqual(d.plistPath, "/Users/you/Library/LaunchAgents/com.example.photo-backup.plist")
        XCTAssertEqual(d.type, "LaunchAgent")
        XCTAssertEqual(d.program, "/bin/bash")
        XCTAssertEqual(d.arguments, ["/bin/bash", "/Users/you/Projects/backup/run.sh"])
        XCTAssertEqual(d.workingDir, "/Users/you/Projects/backup")
        XCTAssertEqual(d.stdoutPath, "/Users/you/Library/Logs/backup.log")
        XCTAssertEqual(d.runs, 686)
        XCTAssertEqual(d.lastExit, 0)
        XCTAssertFalse(d.neverExited)
        XCTAssertNil(d.pid)
    }

    func testServicePrintNeverRan() throws {
        let d = try XCTUnwrap(parseServicePrint(Fixture.neverRanService))
        XCTAssertEqual(d.runs, 0)
        XCTAssertTrue(d.neverExited)
        XCTAssertNil(d.lastExit)
    }

    func testServicePrintIgnoresNestedKeys() throws {
        // pid-local endpoints 안의 "pid = 99999" 를 서비스 PID 로 읽으면 안 된다
        let d = try XCTUnwrap(parseServicePrint(Fixture.runningService))
        XCTAssertEqual(d.pid, 4821)
        XCTAssertEqual(d.runs, 1)
        XCTAssertTrue(d.neverExited)
    }

    func testServicePrintSignal() throws {
        let d = try XCTUnwrap(parseServicePrint(Fixture.signalledService))
        XCTAssertEqual(d.lastExit, -11)
        XCTAssertEqual(d.pid, 412)
        XCTAssertEqual(d.commandLine, ["/Library/Vendor/bin/realnamed"])
    }

    func testServicePrintSMAppService() throws {
        let d = try XCTUnwrap(parseServicePrint(Fixture.smAppService))
        XCTAssertNil(d.plistPath)
        XCTAssertEqual(d.submittedBy, "smd")
        XCTAssertEqual(d.managedBy, "com.apple.xpc.ServiceManagement")
        XCTAssertEqual(d.parentBundleID, "com.example.mainapp")
        XCTAssertEqual(d.programIdentifier, "Contents/Library/LoginItems/ExampleHelper.app")
        XCTAssertEqual(d.commandLine, ["Contents/Library/LoginItems/ExampleHelper.app"])
    }

    func testServicePrintEmbeddedPathWithSpaces() throws {
        let d = try XCTUnwrap(parseServicePrint(Fixture.embeddedService))
        XCTAssertEqual(d.plistPath, "/Applications/Example Suite.app/Contents/Library/LaunchAgents/com.example.embedded.agent.plist")
        XCTAssertEqual(d.arguments, ["/Applications/Example Suite.app/Contents/MacOS/agent", "--background"])
    }

    func testParseProcessesFiltersByUIDAndSystemPaths() {
        let ps = """
            1     0   0.0  0.1    05-00:02:31 /sbin/launchd
          812   501  12.5  1.2       01:10:03 /Applications/Example Suite.app/Contents/MacOS/Example Suite
          900   501   0.3  0.2          10:44 /usr/libexec/exampled
          901   501   3.0  0.4          02:11 /opt/homebrew/bin/node
          902   502   9.0  0.4          02:11 /opt/homebrew/bin/node
        """
        let procs = parseProcesses(ps, uid: 501)
        XCTAssertEqual(procs.map(\.id), [812, 901])
        XCTAssertEqual(procs[0].name, "Example Suite")   // 공백이 든 경로도 통째로
        XCTAssertEqual(procs[0].elapsed, "01:10:03")
    }
}

final class PlistParserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testScheduled() throws {
        let data = Fixture.plist(["Label": "com.example.a", "ProgramArguments": ["/bin/bash", "/Users/you/run.sh"],
                                  "StartCalendarInterval": ["Hour": 2, "Minute": 30], "RunAtLoad": true,
                                  "StandardOutPath": "/tmp/a.log"])
        let info = try XCTUnwrap(parsePlist(data, system: false, now: now))
        XCTAssertEqual(info.label, "com.example.a")
        XCTAssertEqual(info.kind, .scheduled)
        XCTAssertEqual(info.schedule, "매일 02:30 · 로그인 시에도")
        XCTAssertNotNil(info.nextRun)
        XCTAssertEqual(info.stdoutPath, "/tmp/a.log")
    }

    func testCalendarArrayAndInterval() throws {
        let many = Fixture.plist(["Label": "x", "StartCalendarInterval": [["Hour": 9, "Minute": 0], ["Hour": 18, "Minute": 30]]])
        XCTAssertEqual(try XCTUnwrap(parsePlist(many, system: false, now: now)).schedule, "매일 09:00, 매일 18:30")
        let iv = Fixture.plist(["Label": "x", "StartInterval": 1800])
        let info = try XCTUnwrap(parsePlist(iv, system: false, now: now))
        XCTAssertEqual(info.schedule, "30분마다")
        XCTAssertNil(info.nextRun)
    }

    func testKinds() throws {
        func kind(_ d: [String: Any], system: Bool = false) throws -> (Kind, String) {
            let i = try XCTUnwrap(parsePlist(Fixture.plist(d), system: system, now: now))
            return (i.kind, i.schedule)
        }
        XCTAssertEqual(try kind(["KeepAlive": true]).0, .resident)
        XCTAssertEqual(try kind(["KeepAlive": ["SuccessfulExit": false]]).1, "조건부 상주")
        XCTAssertEqual(try kind(["KeepAlive": false, "RunAtLoad": true]).0, .atLogin)
        XCTAssertEqual(try kind(["MachServices": ["com.example.svc": true]]).0, .trigger)
        XCTAssertEqual(try kind(["RunAtLoad": true], system: true).1, "부팅 시 1회")
        XCTAssertEqual(try kind([:]).0, .manual)
    }

    func testProgramOverridesFirstArgument() throws {
        let data = Fixture.plist(["Program": "/usr/local/bin/real", "ProgramArguments": ["shown-name", "--flag"]])
        XCTAssertEqual(try XCTUnwrap(parsePlist(data, system: false, now: now)).args, ["/usr/local/bin/real", "--flag"])
    }

    func testAssociatedBundleIdentifiers() throws {
        let one = Fixture.plist(["AssociatedBundleIdentifiers": "com.example.mainapp"])
        XCTAssertEqual(try XCTUnwrap(parsePlist(one, system: false, now: now)).associatedBundleIDs, ["com.example.mainapp"])
        let many = Fixture.plist(["AssociatedBundleIdentifiers": ["com.example.a", "com.example.b"]])
        XCTAssertEqual(try XCTUnwrap(parsePlist(many, system: false, now: now)).associatedBundleIDs, ["com.example.a", "com.example.b"])
    }

    func testGarbageIsNil() {
        XCTAssertNil(parsePlist(Data("not a plist".utf8), system: false, now: now))
        // plist 이긴 하지만 딕셔너리가 아닌 경우
        XCTAssertNil(parsePlist(Fixture.plist(["a", "b"]), system: false, now: now))
    }

    func testResolveOwner() {
        let home = Fixture.home
        XCTAssertEqual(resolveOwner(associated: ["com.example.mainapp"], parentBundleID: "com.other", paths: [], source: .userAgent, home: home),
                       .bundleID("com.example.mainapp"))
        XCTAssertEqual(resolveOwner(associated: [], parentBundleID: "com.example.mainapp", paths: ["/Applications/Other.app/x"], source: .appEmbedded, home: home),
                       .bundleID("com.example.mainapp"))
        XCTAssertEqual(resolveOwner(associated: [], parentBundleID: nil,
                                    paths: ["/Applications/Example Suite.app/Contents/MacOS/agent"], source: .globalAgent, home: home),
                       .app(path: "/Applications/Example Suite.app"))
        XCTAssertEqual(resolveOwner(associated: [], parentBundleID: nil, paths: ["/bin/bash", "\(home)/Projects/backup/run.sh"], source: .userAgent, home: home),
                       .selfMade)
        // ~/Library 아래 도우미는 내가 만든 것이 아니다
        XCTAssertEqual(resolveOwner(associated: [], parentBundleID: nil, paths: ["\(home)/Library/Application Support/Vendor/helper"], source: .userAgent, home: home),
                       .unknown)
        // 내 에이전트가 아니면 홈 폴더 경로여도 추정하지 않는다
        XCTAssertEqual(resolveOwner(associated: [], parentBundleID: nil, paths: ["\(home)/bin/tool"], source: .daemon, home: home), .unknown)
    }
}
