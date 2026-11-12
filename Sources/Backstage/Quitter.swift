import AppKit
import Darwin
import BackstageCore

/// 프로그램 끄기. 앱이면 앱에 정상 종료를 요청하고, 아니면 SIGTERM 을 보낸다.
/// PID 는 재사용되므로 신호를 보내기 전에 그 PID 가 아직 ps 가 본 프로그램인지 확인한다.
enum Quitter {
    /// 확인창에서 "종료"를 누른 뒤 강제 종료 버튼을 보여 주기까지 기다리는 시간
    static let grace = 5

    static func livePath(_ pid: Int) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(Int32(pid), &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// 아직 살아 있는, ps 가 본 것과 같은 프로세스들
    static func alive(_ g: AppGroup) -> [Proc] {
        g.procs.filter { p in livePath(p.id).map { sameProgram(psPath: p.path, livePath: $0) } ?? false }
    }

    static func runningApp(_ g: AppGroup) -> NSRunningApplication? {
        guard let app = g.appPath else { return nil }
        let want = URL(fileURLWithPath: app).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == want }
    }

    static func requestQuit(_ g: AppGroup) {
        if let app = runningApp(g), app.terminate() { return }
        for p in alive(g) { kill(pid_t(p.id), SIGTERM) }
    }

    static func forceQuit(_ g: AppGroup) {
        runningApp(g)?.forceTerminate()
        for p in alive(g) { kill(pid_t(p.id), SIGKILL) }
    }
}
