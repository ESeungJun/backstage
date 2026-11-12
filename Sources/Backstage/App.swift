// Backstage: launchd 예약/상주 작업과 내 프로세스를 보여주는 메뉴바 앱. 작업은 읽기만 하고, 프로그램은 사용자가 고른 것만 끈다.
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
            openWindow: { [weak self] id in self?.showWindow(select: id) },
            openProcs: { [weak self] in self?.showWindow(select: nil, tab: 1) }))

        store.onArrivals = { [weak self] jobs in self?.notifier.announce(jobs) }
        notifier.onOpen = { [weak self] id in self?.showWindow(select: id) }

        // 스크린샷용: 시작하면서 전체 보기 창을 띄운다
        if args.contains("--window") { showWindow(select: store.demo ? store.jobs.first(where: \.failed)?.id : nil) }

        // 배지는 작업 목록과 확인 표시 둘 다에 따라 바뀐다
        cancel = store.$jobs.combineLatest(store.$acknowledged).receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateIcon() }
        updateIcon()
    }

    /// 내 에이전트가 새로 실패했을 때만 경고 아이콘 + 개수. 평소에는 앱 아이콘과 같은 캐릭터 실루엣.
    private func updateIcon() {
        let n = store.attention.count
        let img = n > 0 ? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Backstage") : Self.glyph
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
            store.setViewingProcs(true, refreshNow: false)   // 패널의 'CPU 제일 많이 쓰는 앱' 카드용
            store.setViewing(true)   // 열 때 바로 새로 읽는다
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setViewingProcs(false)
        store.setViewing(false)
    }

    /// 18pt 템플릿 캐릭터: 블롭 실루엣에 두 눈과 웃는 입을 뚫는다(앱의 BlobPainter 와 같은 곡선).
    static let glyph: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let ctx = NSGraphicsContext.current!.cgContext
            let W: CGFloat = 14, H: CGFloat = 13.5
            let b = CGPoint(x: r.midX, y: 2), x0 = b.x - W / 2, top = b.y + H
            let body = CGMutablePath()
            body.move(to: CGPoint(x: x0, y: b.y))
            body.addCurve(to: CGPoint(x: b.x, y: top), control1: CGPoint(x: x0 - 0.3, y: top - H * 0.25), control2: CGPoint(x: x0 + W * 0.18, y: top))
            body.addCurve(to: CGPoint(x: x0 + W, y: b.y), control1: CGPoint(x: x0 + W * 0.82, y: top), control2: CGPoint(x: x0 + W + 0.3, y: top - H * 0.25))
            body.closeSubpath()
            ctx.addPath(body); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
            ctx.setBlendMode(.clear)
            let cy = top - H * 0.42, gap: CGFloat = 2.6, e: CGFloat = 1.25
            for x in [b.x - gap, b.x + gap] { ctx.fillEllipse(in: CGRect(x: x - e, y: cy - e, width: 2 * e, height: 2 * e)) }
            ctx.setLineWidth(1.1); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: b.x - 1.4, y: cy - 2.6))
            ctx.addQuadCurve(to: CGPoint(x: b.x + 1.4, y: cy - 2.6), control: CGPoint(x: b.x, y: cy - 3.8))
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Backstage"
        return img
    }()

    private func showWindow(select id: Job.ID?, tab: Int? = nil) {
        if popover.isShown { popover.performClose(nil) }
        if let id { store.selection = id }
        if let t = tab ?? (id == nil ? nil : 0) { store.windowTab = t }
        if window == nil {
            let vis = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
            let size = CGSize(width: min(1240, vis.width - 80), height: min(760, vis.height - 80))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Backstage"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentViewController = NSHostingController(rootView: ContentView(store: store, tab: args.contains("--procs") ? 1 : 0))
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
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        store.selection = store.jobs.first(where: \.failed)?.id
        let shots: [(String, CGSize, AnyView)] = [
            ("popover.png", PopoverView.size, AnyView(PopoverView(store: store, login: login, notifier: notifier).environment(\.stillCharacters, true))),
            ("window.png", CGSize(width: 1240, height: 720), AnyView(ContentView(store: store))),
            ("procs.png", CGSize(width: 1240, height: 720), AnyView(ContentView(store: store, tab: 1).environment(\.stillCharacters, true))),
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
