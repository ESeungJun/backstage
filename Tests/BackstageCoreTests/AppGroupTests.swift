import XCTest
@testable import BackstageCore

final class AppGroupTests: XCTestCase {
    let browser = "/Applications/Example Browser.app"

    func testOutermostBundle() {
        XCTAssertEqual(outermostAppBundle("\(browser)/Contents/MacOS/Example Browser"), browser)
        XCTAssertEqual(outermostAppBundle("\(browser)/Contents/Frameworks/X.framework/Helpers/Helper (Renderer).app/Contents/MacOS/Helper (Renderer)"), browser)
        XCTAssertNil(outermostAppBundle("/opt/homebrew/bin/node"))
        XCTAssertNil(outermostAppBundle("node"))
    }

    func testGroupsHelpersIntoOneApp() {
        let procs = [
            Proc(id: 1, cpu: 3, mem: 1, elapsed: "01:00:00", path: "\(browser)/Contents/MacOS/Example Browser"),
            Proc(id: 2, cpu: 20, mem: 2, elapsed: "10:00", path: "\(browser)/Contents/Frameworks/H.app/Contents/MacOS/H"),
            Proc(id: 3, cpu: 5, mem: 1, elapsed: "05:00", path: "/opt/homebrew/bin/node"),
            Proc(id: 4, cpu: 1, mem: 1, elapsed: "05:00", path: "/opt/homebrew/bin/node"),
        ]
        let g = groupByApp(procs)
        // 앱이 아닌 것은 같은 실행 파일이라도 따로 둔다
        XCTAssertEqual(g.map(\.name), ["Example Browser", "node", "node"])
        XCTAssertEqual(g[0].cpu, 23)
        XCTAssertEqual(g[0].pids, [1, 2])
        XCTAssertEqual(g[0].appPath, browser)
        XCTAssertEqual(g[0].elapsedSeconds, 3600)
        XCTAssertNil(g[1].appPath)
        XCTAssertEqual(g[1].cpu, 5)
        XCTAssertEqual(g[1].pids, [3])
    }

    func testElapsed() {
        XCTAssertEqual(parseElapsed("12:44"), 764)
        XCTAssertEqual(parseElapsed("03:12:44"), 3 * 3600 + 764)
        XCTAssertEqual(parseElapsed("2-01:00:00"), 2 * 86400 + 3600)
        XCTAssertNil(parseElapsed("x"))
        XCTAssertEqual(describeElapsed(3 * 3600 + 12 * 60), "3시간 12분")
        XCTAssertEqual(describeElapsed(2 * 86400 + 3600), "2일 1시간")
        XCTAssertEqual(describeElapsed(30), "1분 안")
    }

    func testMood() {
        XCTAssertEqual(CPUMood(cpu: 0.2), .sleep)
        XCTAssertEqual(CPUMood(cpu: 9), .happy)
        XCTAssertEqual(CPUMood(cpu: 38), .busy)
        XCTAssertEqual(CPUMood(cpu: 50), .sweat)
        XCTAssertEqual(CPUMood(cpu: 142), .boil)
    }

    func testCanQuit() {
        let app = AppGroup(id: browser, name: "B", appPath: browser,
                           procs: [Proc(id: 10, cpu: 1, mem: 1, elapsed: "1:00", path: "\(browser)/Contents/MacOS/B")])
        XCTAssertTrue(canQuit(app, selfPID: 99, selfBundle: "/Applications/Backstage.app"))
        XCTAssertFalse(canQuit(app, selfPID: 10, selfBundle: nil))
        XCTAssertFalse(canQuit(app, selfPID: 99, selfBundle: browser))
        let sys = AppGroup(id: "/usr/bin/x", name: "x", appPath: nil,
                           procs: [Proc(id: 11, cpu: 1, mem: 1, elapsed: "1:00", path: "/usr/bin/x")])
        XCTAssertFalse(canQuit(sys, selfPID: 99, selfBundle: nil))
    }

    func testSameProgram() {
        XCTAssertTrue(sameProgram(psPath: "/opt/a/node", livePath: "/opt/a/node"))
        XCTAssertTrue(sameProgram(psPath: "/tmp/x/stub", livePath: "/private/tmp/x/stub"))
        XCTAssertTrue(sameProgram(psPath: "/opt/homebrew/bin/node", livePath: "/opt/homebrew/Cellar/node/22.0/bin/node"))
        XCTAssertFalse(sameProgram(psPath: "/opt/a/node", livePath: "/opt/a/python"))
        XCTAssertTrue(sameProgram(psPath: "node", livePath: "/opt/a/node"))
        XCTAssertFalse(sameProgram(psPath: "node", livePath: "/opt/a/python"))
    }
}
