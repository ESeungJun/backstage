import Foundation
@testable import BackstageCore

// 실제 `launchctl print` 출력 형태를 본뜬 고정 자료. 라벨·경로는 전부 지어낸 것이다.

enum Fixture {
    static let home = "/Users/you"
    static let uid = 501

    static let guiDomain = """
    gui/501 = {
    \ttype = login
    \thandle = 100003
    \tactive count = 474
    \tsecurity context = {
    \t\tuid = 501
    \t\tasid = 100003
    \t}

    \tenvironment = {
    \t\tSSH_AUTH_SOCK => /var/run/com.apple.launchd.AbCdEfGhIj/Listeners
    \t}

    \tservices = {
    \t\t   32487      - \tapplication.com.example.notes.1152921500311894402.1152921500311894407
    \t\t   67468   (pe) \tcom.apple.exampled
    \t\t       0      0 \tcom.apple.example.useragent
    \t\t       0      0 \tcom.example.photo-backup
    \t\t       0    126 \tcom.example.broken-backup
    \t\t    4821      - \tcom.example.notes-server
    \t\t       0    -15 \tcom.example.interrupted
    \t\t    7001   (jt) \tcom.example.updater.helper
    \t\t       0      0 \tcom.example.loginitem
    \t\t    9100      - \tcom.example.embedded.agent
    \t\t       0      0 \tcom.example.fresh
    \t\t    2222      - \tcom.vendor.shared-agent
    \t}

    \tunmanaged processes = {
    \t\tcom.apple.xpc.launchd.unmanaged.example.501 = {
    \t\t\tactive count = 1
    \t\t}
    \t}

    \tendpoints = {
    \t\t   0x1a03    M   D   com.example.notes-server
    \t}

    \tdisabled services = {
    \t\t"com.example.switched-off" => disabled
    \t\t"com.example.photo-backup" => enabled
    \t}

    \tproperties = uncorked | audit check done | bootstrap
    }
    """

    static let systemDomain = """
    system = {
    \ttype = system
    \thandle = 0
    \tsubdomains = {
    \t\tcom.apple.xpc.launchd.domain.pid.exampled.123
    \t\tservices = {
    \t\t}
    \t}

    \tservices = {
    \t\t     334      - \tcom.vendor.netd
    \t\t       0      1 \tcom.vendor.locked
    \t\t     900   (pe) \tcom.apple.exampled
    \t\t     412    -11 \tcom.vendor.realname
    \t\t       0      0 \torg.example.printd
    \t\t       0      0 \tcom.vendor.task.temp
    \t}

    \tdisabled services = {
    \t\t"com.vendor.olddaemon" => disabled
    \t}
    }
    """

    /// 여러 번 돈 예약 작업(지금은 쉬는 중)
    static let scheduledService = """
    gui/501/com.example.photo-backup = {
    \tactive count = 0
    \tpath = /Users/you/Library/LaunchAgents/com.example.photo-backup.plist
    \ttype = LaunchAgent
    \tstate = not running

    \tprogram = /bin/bash
    \targuments = {
    \t\t/bin/bash
    \t\t/Users/you/Projects/backup/run.sh
    \t}

    \tworking directory = /Users/you/Projects/backup

    \tstdout path = /Users/you/Library/Logs/backup.log
    \tstderr path = /Users/you/Library/Logs/backup.log
    \tinherited environment = {
    \t\tSSH_AUTH_SOCK => /var/run/com.apple.launchd.AbCdEfGhIj/Listeners
    \t}

    \tdomain = gui/501 [100003]
    \tasid = 100003
    \tminimum runtime = 10
    \texit timeout = 5
    \truns = 686
    \tlast exit code = 0

    \tevent triggers = {
    \t\tcom.example.photo-backup.268435573 => {
    \t\t\tkeepalive = 0
    \t\t\tservice = com.example.photo-backup
    \t\t\tstream = com.apple.launchd.calendarinterval
    \t\t\tdescriptor = {
    \t\t\t\t"Minute" => 30
    \t\t\t\t"Hour" => 2
    \t\t\t}
    \t\t}
    \t}

    \tspawn type = background (6)
    \tjetsam priority = 40
    \tproperties = runatload | inferred program
    }
    """

    /// 등록만 되고 아직 돌지 않은 작업
    static let neverRanService = """
    gui/501/com.example.fresh = {
    \tactive count = 0
    \tpath = /Users/you/Library/LaunchAgents/com.example.fresh.plist
    \ttype = LaunchAgent
    \tstate = not running

    \tprogram = /Users/you/bin/fresh
    \targuments = {
    \t\t/Users/you/bin/fresh
    \t}

    \truns = 0
    \tlast exit code = (never exited)
    }
    """

    /// 돌고 있는 상주 작업(한 번도 끝난 적 없음)
    static let runningService = """
    gui/501/com.example.notes-server = {
    \tactive count = 3
    \tpath = /Users/you/Library/LaunchAgents/com.example.notes-server.plist
    \ttype = LaunchAgent
    \tstate = running

    \tprogram = /usr/local/bin/node
    \targuments = {
    \t\t/usr/local/bin/node
    \t\t/Users/you/Projects/notes/server.js
    \t}

    \truns = 1
    \tpid = 4821
    \timmediate reason = speculative
    \tforks = 0
    \texecs = 1
    \tlast exit code = (never exited)

    \tpid-local endpoints = {
    \t\t"com.example.portname" = {
    \t\t\tport = 0x1c403
    \t\t\tactive = 1
    \t\t\tpid = 99999
    \t\t}
    \t}
    }
    """

    /// 신호로 죽었다가 다시 뜬 서비스
    static let signalledService = """
    system/com.vendor.realname = {
    \tactive count = 1
    \tpath = /Library/LaunchDaemons/com.vendor.daemon-file.plist
    \ttype = LaunchDaemon
    \tstate = running

    \tprogram = /Library/Vendor/bin/realnamed
    \truns = 2
    \tpid = 412
    \tlast terminating signal = Segmentation fault: 11
    }
    """

    /// SMAppService 로 등록된 로그인 항목(설정 파일 경로가 없다)
    static let smAppService = """
    gui/501/com.example.loginitem = {
    \tactive count = 0
    \tpath = (submitted by smd[412])
    \ttype = Submitted
    \tmanaged_by = com.apple.xpc.ServiceManagement
    \tstate = not running

    \tprogram identifier = Contents/Library/LoginItems/ExampleHelper.app (mode: 1)
    \tparent bundle identifier = com.example.mainapp
    \tparent bundle version = 42
    \tBTM uuid = 00000000-0000-4000-8000-000000000001
    \tinherited environment = {
    \t\tSSH_AUTH_SOCK => /var/run/com.apple.launchd.AbCdEfGhIj/Listeners
    \t}

    \truns = 1
    \tlast exit code = 0
    }
    """

    /// 앱 번들 안 plist 로 등록된 에이전트
    static let embeddedService = """
    gui/501/com.example.embedded.agent = {
    \tactive count = 1
    \tpath = /Applications/Example Suite.app/Contents/Library/LaunchAgents/com.example.embedded.agent.plist
    \ttype = LaunchAgent
    \tstate = running

    \tprogram = /Applications/Example Suite.app/Contents/MacOS/agent
    \targuments = {
    \t\t/Applications/Example Suite.app/Contents/MacOS/agent
    \t\t--background
    \t}

    \truns = 3
    \tpid = 9100
    \tlast exit code = 0
    }
    """

    /// 프로그램이 실행 중에 직접 올린 서비스
    static let submittedService = """
    gui/501/com.example.updater.helper = {
    \tactive count = 1
    \tpath = (submitted by ExampleUpdater[7000])
    \ttype = Submitted
    \tstate = running

    \tprogram = /Users/you/Library/Application Support/ExampleUpdater/helper
    \tstdout path = /Users/you/Library/Logs/ExampleUpdater/helper.log
    \tstderr path = /Users/you/Library/Logs/ExampleUpdater/helper.log
    \truns = 4
    \tpid = 7001
    }
    """

    /// 라벨은 com.apple 이 아니지만 macOS 기본 서비스
    static let builtinService = """
    system/org.example.printd = {
    \tactive count = 0
    \tpath = /System/Library/LaunchDaemons/org.example.printd.plist
    \ttype = LaunchDaemon
    \tstate = not running

    \tprogram = /usr/sbin/printd
    \truns = 1
    \tlast exit code = 0
    }
    """

    /// 임시 plist 로 올린 뒤 파일을 지운 서비스
    static let tempPlistService = """
    system/com.vendor.task.temp = {
    \tactive count = 0
    \tpath = /Library/Application Support/Vendor/tmp/com.vendor.task.temp.plist
    \ttype = LaunchDaemon
    \tstate = not running

    \tprogram = /Library/Vendor/bin/task
    \truns = 1
    \tlast exit code = 0
    }
    """

    static let notFound = """
    Bad request.
    Could not find service "com.example.missing" in domain for user gui: 501
    """

    static func plist(_ dict: Any) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

/// 정해 둔 출력을 돌려주고, 무엇을 몇 번 불렀는지 적어 두는 가짜 실행기.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    var outputs: [String: String] = [:]
    private(set) var calls: [String] = []

    func run(_ exe: String, _ args: [String]) -> String {
        let key = args.joined(separator: " ")
        calls.append(key)
        return outputs[key] ?? Fixture.notFound
    }
}

struct FakeFiles: FileSource {
    var dirs: [String: [String]] = [:]
    var data: [String: Data] = [:]
    var present: Set<String> = []

    func list(_ dir: String) -> [String] { dirs[dir] ?? [] }
    func contents(_ path: String) -> Data? { data[path] }
    func exists(_ path: String) -> Bool { present.contains(path) || data[path] != nil }
}
