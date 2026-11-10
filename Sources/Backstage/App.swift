// Backstage: launchd 예약/상주 작업과 내 프로세스를 보여주는 읽기 전용 메뉴바 앱
import SwiftUI
import AppKit
import Combine
import BackstageCore

/// 메뉴바 아이콘 + 누르면 내려오는 요약 패널 + "전체 보기" 창
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let args = CommandLine.arguments
    private lazy var store = Store(demo: args.contains("--demo") || args.contains("--snapshot"))
    private lazy var login = LoginItem(demo: store.demo)
    private let notifier = Notifier()
    private var window: NSWindow?
    private var cancel: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        OwnerLookup.shared.demo = store.demo

        // 개발용: 화면에 아무것도 띄우지 않고 예시 화면을 PNG 로 떠서 끝낸다
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        self.item = item

        popover.behavior = .transient          // 바깥을 누르면 닫힘
        popover.animates = false
        popover.delegate = self
        popover.contentSize = PopoverView.size
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            store: store, login: login, notifier: notifier,
            openWindow: { [weak self] id in self?.showWindow(select: id) }))

        store.onArrivals = { [weak self] jobs in self?.notifier.announce(jobs) }
        notifier.onOpen = { [weak self] id in self?.showWindow(select: id) }

        // 스크린샷용: 시작하면서 전체 보기 창을 띄운다
        if args.contains("--window") { showWindow(select: store.demo ? store.jobs.first(where: \.failed)?.id : nil) }

        // 배지는 작업 목록과 확인 표시 둘 다에 따라 바뀐다
        cancel = store.$jobs.combineLatest(store.$acknowledged).receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateIcon() }
        updateIcon()
    }

    /// 내 에이전트가 새로 실패했을 때만 경고 아이콘 + 개수. 평소에는 막 아이콘.
    private func updateIcon() {
        let n = store.attention.count
        let name = n > 0 ? "exclamationmark.triangle.fill" : "curtains.closed"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Backstage")
            ?? NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: "Backstage")
        img?.isTemplate = true
        item?.button?.image = img
        item?.button?.title = n > 0 ? " \(n)" : ""
        item?.button?.toolTip = n > 0 ? "마지막 실행이 실패한 내 작업 \(n)개" : "Backstage"
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            store.setViewing(true)   // 열 때 바로 새로 읽는다
        }
    }

    func popoverDidClose(_ notification: Notification) { store.setViewing(false) }

    private func showWindow(select id: Job.ID?) {
        if popover.isShown { popover.performClose(nil) }
        if let id { store.selection = id }
        if window == nil {
            let vis = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            let size = CGSize(width: min(1240, vis.width - 80), height: min(760, vis.height - 80))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Backstage"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentViewController = NSHostingController(rootView: ContentView(store: store))
            w.setContentSize(size)
            w.center()
            window = w
        }
        guard let w = window else { return }
        if !w.isVisible { store.setViewing(true) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { store.setViewing(false) }

    /// 예시 데이터 화면을 화면에 올리지 않은 창에서 그려 PNG 로 저장한다.
    private func snapshot(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store.selection = store.jobs.first(where: \.failed)?.id
        let shots: [(String, CGSize, AnyView)] = [
            ("popover.png", PopoverView.size, AnyView(PopoverView(store: store, login: login, notifier: notifier))),
            ("window.png", CGSize(width: 1240, height: 720), AnyView(ContentView(store: store))),
        ]
        for (name, size, view) in shots {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: size)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))   // 표가 줄을 채울 시간
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
    }
}

@main
struct BackstageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // 개발용: 화면 없이 수집 비용만 재고 끝낸다
        if CommandLine.arguments.contains("--probe") {
            Store.probe()
            exit(0)
        }
    }

    var body: some Scene { Settings { EmptyView() } }
}
