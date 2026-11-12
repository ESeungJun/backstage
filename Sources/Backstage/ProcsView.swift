import SwiftUI
import AppKit
import BackstageCore

/// "실행 중인 프로그램" 탭. 앱마다 CPU 만큼 뚱뚱한 캐릭터로 보여 주고, 표로도 볼 수 있다.
struct ProcsView: View {
    @ObservedObject var store: Store
    @State private var mode = 0          // 0 캐릭터, 1 표
    @State private var query = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(mode == 0
                     ? "내 계정으로 실행 중인 앱 \(groupByApp(store.procs).count)개 · 프로세스 \(store.procs.count)개 (macOS 기본 시스템 프로세스 제외, CPU 순)"
                     : "내 계정으로 실행 중인 프로그램 \(store.procs.count)개 (macOS 기본 시스템 프로세스 제외, CPU 순)")
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if mode == 1 {
                    TextField("이름·경로 검색", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
                }
                Picker("", selection: $mode) {
                    Text("캐릭터").tag(0)
                    Text("표").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
            }
            if mode == 0 {
                CharacterBoard(store: store, showTable: { mode = 1 })
            } else {
                ProcTable(procs: store.procs.filter { query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) })
            }
        }
        .padding(14)
        // 이 탭이 보일 때만 ps 를 돈다
        .onAppear { store.setViewingProcs(true) }
        .onDisappear { store.setViewingProcs(false) }
    }
}

struct ProcTable: View {
    let procs: [Proc]
    var body: some View {
        Table(procs) {
            TableColumn("이름") { p in Text(p.name).fontWeight(.medium) }.width(min: 160, ideal: 220)
            TableColumn("CPU %") { p in Text(String(format: "%.1f", p.cpu)).foregroundStyle(p.cpu > 50 ? .red : .primary) }.width(60)
            TableColumn("메모리 %") { p in Text(String(format: "%.1f", p.mem)) }.width(70)
            TableColumn("실행 시간") { p in Text(p.elapsed) }.width(90)
            TableColumn("PID") { p in Text("\(p.id)").foregroundStyle(.secondary) }.width(60)
            TableColumn("경로") { p in Text(p.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }
}

// MARK: - 캐릭터 화면

/// 무대(캐릭터들) + 오른쪽 상세 칸 + 종료 확인창
struct CharacterBoard: View {
    @ObservedObject var store: Store
    var showTable: () -> Void
    @State private var selected: AppGroup.ID?
    @State private var quit: QuitFlow?

    var body: some View {
        let groups = groupByApp(store.procs)
        let current = groups.first { $0.id == selected } ?? groups.first

        VStack(spacing: 0) {
            SummaryStrip(groups: groups)
            Divider()
            HStack(spacing: 0) {
                ZStack {
                    Stage(groups: groups, selected: current?.id,
                          pick: { selected = $0 }, showTable: showTable)
                    // 닫힌 확인창의 기다림이 늦게 끝나도 새로 연 확인창을 닫지 않게 표로 맞춘다
                    if let q = quit {
                        QuitSheet(flow: q, close: { if quit?.token == q.token { quit = nil } }, store: store).id(q.token)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Group {
                    if let g = current {
                        AppDetail(group: g, busy: quit != nil, ask: { quit = QuitFlow(group: g) })
                    } else {
                        Text(store.procsLoaded ? "실행 중인 프로그램이 없어요." : "살펴보는 중…")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 260)
            }
        }
        .background(Palette.window)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
    }
}

/// 맨 위 한 줄: 내 프로그램이 쓰는 CPU 합계와 제일 바쁜 앱
struct SummaryStrip: View {
    let groups: [AppGroup]
    var body: some View {
        let (pct, cores) = Self.total(groups)
        HStack(spacing: 10) {
            Text("내 프로그램 CPU")
            CPUBar(pct: pct).frame(maxWidth: 240)
            Text("\(Int(pct.rounded()))% (코어 \(cores)개)")
            Spacer()
            if let busiest = groups.first {
                Text("제일 바쁜 앱: ") + Text(busiest.name).foregroundColor(.primary).bold()
            }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// 내 프로그램이 쓰는 CPU 를 맥 전체(코어 수) 대비 %로
    static func total(_ groups: [AppGroup]) -> (pct: Double, cores: Int) {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return (min(100, groups.reduce(0) { $0 + $1.cpu } / Double(cores)), cores)
    }
}

/// 초록 → 주황 → 빨강으로 차는 가는 막대
struct CPUBar: View {
    let pct: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.floor)
                Capsule().fill(LinearGradient(colors: [Palette.ok, Palette.warm, Palette.hot], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * pct / 100)
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

/// 메뉴바 패널에 들어가는 작은 카드: CPU 를 제일 많이 쓰는 앱 하나만 캐릭터로, 옆에 전체 CPU.
struct BusiestCard: View {
    @ObservedObject var store: Store
    var open: () -> Void

    static let box: CGFloat = 104

    var body: some View {
        let groups = groupByApp(store.procs)
        if let g = groups.first {
            let (pct, cores) = SummaryStrip.total(groups)
            let m = BlobMetrics(cpu: g.cpu)
            HStack(alignment: .center, spacing: 14) {
                Character(group: g, selected: false, showLabel: false)
                    .scaleEffect(min(1, Self.box / (m.height + Character.overTop)), anchor: .bottom)
                    .frame(width: Self.box, height: Self.box, alignment: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.name).fontWeight(.semibold).lineLimit(1)
                    (Text(String(format: "CPU %.1f%%", g.cpu)).foregroundColor(Palette.tint(g.cpu)).bold()
                     + Text(" · \(g.mood.text)")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer().frame(height: 2)
                    Text("내 프로그램 전체 \(Int(pct.rounded()))% (코어 \(cores)개)").font(.caption).foregroundStyle(.secondary)
                    CPUBar(pct: pct)
                    Button("실행 중인 프로그램 \(groups.count)개 보기", action: open)
                        .buttonStyle(.link).font(.caption).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.window))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        } else {
            Text(store.procsLoaded ? "실행 중인 내 프로그램이 없어요." : "살펴보는 중…")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 캐릭터들이 바닥 띠 위에 나란히 선 무대.
/// 무대 높이를 채우도록 캐릭터를 키우고, 그러다 폭이 모자라면 무대에 올리는 수를 줄인다(나머지는 오른쪽 위 '그 밖에' 메뉴).
struct Stage: View {
    /// CPU 순으로 줄 선 전체 앱
    let groups: [AppGroup]
    let selected: AppGroup.ID?
    var pick: (AppGroup.ID) -> Void
    var showTable: () -> Void

    static let floor: CGFloat = 46
    static let gap: CGFloat = 6
    static let most = 7, fewest = 4
    static let maxZoom: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fit(groups, in: geo.size)
            let shown = groups.prefix(fit.count), hidden = Array(groups.dropFirst(fit.count))
            ZStack(alignment: .bottom) {
                Palette.floor.frame(height: Self.floor)
                HStack(alignment: .bottom, spacing: Self.gap) {
                    ForEach(shown) { g in
                        // 버튼이라 키보드(Tab·Space)와 VoiceOver 로도 고를 수 있다
                        Button { pick(g.id) } label: { Character(group: g, selected: g.id == selected, zoom: fit.zoom) }
                            .buttonStyle(.plain)
                    }
                }
                .fixedSize()
                .padding(.bottom, Self.floor)
                .scaleEffect(fit.shrink, anchor: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .overlay(alignment: .topTrailing) {
                if !hidden.isEmpty { more(hidden).padding(12) }
            }
        }
        .frame(minHeight: 380)
        .background(Palette.window)
    }

    /// 무대에 못 올라간 앱. 메뉴에서 골라 상세 칸에 띄우거나 표로 간다.
    func more(_ hidden: [AppGroup]) -> some View {
        Menu {
            ForEach(hidden) { g in
                Button("\(g.name) · \(String(format: "%.1f", g.cpu))%") { pick(g.id) }
            }
            Divider()
            Button("표에서 보기", action: showTable)
        } label: {
            Text("그 밖에 \(hidden.count)개 · 표에서 보기").font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().stroke(Palette.line))
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
    }

    /// 몇 개를 올리고(count) 얼마나 키울지(zoom ≥ 1), 그래도 넘치면 얼마나 줄일지(shrink ≤ 1).
    /// 키울 때는 캐릭터가 직접 크게 그려서 흐려지지 않게 하고, 줄일 때만 scaleEffect 를 쓴다.
    static func fit(_ groups: [AppGroup], in size: CGSize) -> (count: Int, zoom: CGFloat, shrink: CGFloat) {
        let room = size.width - 24
        // 위쪽 여유: '그 밖에' 메뉴 자리 44
        let high = (size.height - floor - 44) / (BlobMetrics(cpu: groups.first?.cpu ?? 0).height + Character.overTop)
        let target = max(1, min(maxZoom, high))
        func layout(_ n: Int) -> (zoom: CGFloat, shrink: CGFloat) {
            let bodies = groups.prefix(n).reduce(0) { $0 + BlobMetrics(cpu: $1.cpu).width }
            let gaps = gap * CGFloat(max(n - 1, 0))
            let zoom = max(1, min(target, (room - gaps) / max(bodies, 1)))
            return (zoom, min(1, room / max(bodies * zoom + gaps, 1)))
        }
        // 많이 올리되, 그 때문에 목표 크기의 80%보다 작아지지는 않게
        let upper = min(most, groups.count)
        for n in stride(from: upper, through: min(fewest, upper), by: -1) {
            let l = layout(n)
            if l.zoom * l.shrink >= target * 0.8 || n == min(fewest, upper) { return (n, l.zoom, l.shrink) }
        }
        return (upper, 1, 1)
    }
}

/// 크기 계산. CPU 200%에서 가장 크고, 넓이가 CPU에 비례해 보이게 제곱근을 쓴다.
struct BlobMetrics {
    let s: CGFloat, W: CGFloat, H: CGFloat
    init(cpu: Double) {
        s = CGFloat(sqrt(min(cpu, 200) / 200))
        W = 44 + s * 118
        H = 48 + s * 96
    }
    var width: CGFloat { W + 16 }
    var height: CGFloat { H + 40 }
}

/// 캐릭터 하나: 말랑한 몸, 머리 위 앱 아이콘 모자, 기분에 따른 얼굴, 이름표.
struct Character: View {
    let group: AppGroup
    let selected: Bool
    /// 1보다 크면 그만큼 크게 그린다. 이름표 글자 크기는 그대로.
    var zoom: CGFloat = 1
    /// 이름표(이름·CPU)를 아래에 붙일지. 옆에 따로 적을 때는 끈다.
    var showLabel = true
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillCharacters) private var still

    /// 몸 밖으로 나가는 김·zz 를 그릴 여유
    static let overTop: CGFloat = 30, overSide: CGFloat = 14

    var body: some View {
        let m = BlobMetrics(cpu: group.cpu)
        let painter = BlobPainter(cpu: group.cpu, m: m)
        Group {
            if reduceMotion || still {
                // 움직임 줄이기·스크린샷: 멈춘 한 장
                Canvas { ctx, _ in
                    ctx.scaleBy(x: zoom, y: zoom)
                    ctx.translateBy(x: Self.overSide, y: Self.overTop)
                    painter.drawBody(&ctx, icon: ctx.resolve(AppIcon.image(for: group)))
                    painter.drawEffects(&ctx, time: 0.5)   // 땀·zz 는 멈춘 채로 보인다(시안과 같음)
                }
            } else {
                LiveBlob(painter: painter, icon: AppIcon.nsImage(for: group), zoom: zoom, key: "\(group.id)|\(group.cpu)|\(zoom)")
            }
        }
        .frame(width: (m.width + Self.overSide * 2) * zoom, height: (m.height + Self.overTop) * zoom)
        .padding(.horizontal, -Self.overSide * zoom).padding(.top, -Self.overTop * zoom)
        .frame(width: m.width * zoom, height: m.height * zoom)
        .overlay(alignment: .bottom) {
            if showLabel {
                VStack(spacing: 0) {
                    Text(group.name).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    Text(String(format: "%.1f%%", group.cpu)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1).fixedSize()
                .offset(y: 40)
            }
        }
        .offset(y: hover && !reduceMotion ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement()
        .accessibilityLabel("\(group.name), CPU \(String(format: "%.1f", group.cpu))%, \(group.mood.text)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct StillCharactersKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// 스크린샷처럼 움직임 없이 한 장으로 그릴 때
    var stillCharacters: Bool {
        get { self[StillCharactersKey.self] }
        set { self[StillCharactersKey.self] = newValue }
    }
}

/// 움직이는 캐릭터. 몸은 그림 한 장으로 굽고, 숨쉬기·떨기·땀·김·zz 는 Core Animation 에 맡긴다.
/// 애니메이션이 창 서버에서 돌아서 앱은 프레임마다 아무것도 계산하지 않는다(CPU 를 보는 화면이 CPU 를 먹지 않게).
struct LiveBlob: NSViewRepresentable {
    let painter: BlobPainter
    let icon: NSImage
    var zoom: CGFloat = 1
    let key: String

    func makeNSView(context: Context) -> BlobLayerView { BlobLayerView() }
    func updateNSView(_ v: BlobLayerView, context: Context) {
        guard v.key != key else { return }
        v.key = key
        v.build(painter: painter, icon: icon, zoom: zoom)
    }
}

final class BlobLayerView: NSView {
    var key = ""
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // 처음 크기가 정해질 때와 크기가 바뀔 때 다시 굽는다
        if pending != nil, layer?.sublayers?.first?.frame.size != bounds.size { rebuild() }
    }

    private var pending: (BlobPainter, NSImage, CGFloat)?
    func build(painter: BlobPainter, icon: NSImage, zoom: CGFloat) { pending = (painter, icon, zoom); rebuild() }

    private func rebuild() {
        guard let (p, icon, zoom) = pending, let host = layer, bounds.width > 0 else { return }
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        let ox = Character.overSide, oy = Character.overTop
        // 크게 그릴 때도 또렷하게 그 배율만큼 촘촘히 굽는다
        let scale = (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * zoom

        // 원래 크기로 그린 뒤 통째로 zoom 배 키운다. 왼쪽 위 모서리 기준.
        let base = CGRect(x: 0, y: 0, width: bounds.width / zoom, height: bounds.height / zoom)
        let stage = CALayer()
        stage.anchorPoint = .zero
        stage.bounds = base
        stage.position = .zero
        stage.transform = CATransform3DMakeScale(zoom, zoom, 1)
        host.addSublayer(stage)

        // 바깥 층은 떨기(가로 1pt), 안쪽 층은 바닥 가운데를 기준으로 숨쉬기
        let shiver = CALayer(); shiver.frame = base
        let breathe = CALayer()
        breathe.bounds = base
        breathe.anchorPoint = CGPoint(x: (ox + p.cx) / base.width, y: (oy + p.h) / base.height)
        breathe.position = CGPoint(x: ox + p.cx, y: oy + p.h)
        shiver.addSublayer(breathe)
        stage.addSublayer(shiver)

        let art = ImageRenderer(content: Canvas { ctx, _ in
            ctx.translateBy(x: ox, y: oy)
            p.drawBody(&ctx, icon: ctx.resolve(Image(nsImage: icon)))
        }.frame(width: base.width, height: base.height))
        art.scale = scale
        let body = CALayer()
        body.frame = breathe.bounds
        body.contents = art.cgImage
        body.contentsScale = scale
        breathe.addSublayer(body)

        let now = CACurrentMediaTime()
        func loop(_ a: CAAnimation, delay: Double = 0) -> CAAnimation {
            a.repeatCount = .infinity
            a.beginTime = now + delay
            a.fillMode = .backwards
            a.isRemovedOnCompletion = false
            return a
        }
        func basic(_ path: String, _ from: Double, _ to: Double, _ dur: Double, _ timing: CAMediaTimingFunctionName, reverse: Bool) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: path)
            a.fromValue = from; a.toValue = to; a.duration = dur; a.autoreverses = reverse
            a.timingFunction = CAMediaTimingFunction(name: timing)
            return a
        }

        // 숨쉬기
        let g = CAAnimationGroup()
        g.animations = [basic("transform.scale.x", 1, 1.04, p.period / 2, .easeInEaseOut, reverse: true),
                        basic("transform.scale.y", 1, 0.95, p.period / 2, .easeInEaseOut, reverse: true)]
        g.duration = p.period
        breathe.add(loop(g), forKey: "breathe")
        if p.cpu >= 50 { shiver.add(loop(basic("transform.translation.x", 0, 1, 0.09, .linear, reverse: true)), forKey: "shiver") }

        let (W, H) = (p.m.W, p.m.H)
        let mood = p.mood
        if mood == .sweat || mood == .boil {
            for (x, y, d) in [(p.x0 + W - 6, p.y0 + H * 0.25, 0.0), (p.x0 + 6, p.y0 + H * 0.35, 0.5)] {
                let drop = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 4, y: 7))
                path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -4, y: 7))
                drop.path = path
                drop.fillColor = NSColor(BlobPainter.sweat).cgColor
                drop.contentsScale = scale
                drop.position = CGPoint(x: ox + x, y: oy + y)
                drop.opacity = 0
                let fall = basic("transform.translation.y", -4, 16, 1.1, .easeIn, reverse: false)
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 0]; fade.keyTimes = [0, 0.2, 1]; fade.duration = 1.1
                let both = CAAnimationGroup(); both.animations = [fall, fade]; both.duration = 1.1
                drop.add(loop(both, delay: d), forKey: "drop")
                breathe.addSublayer(drop)
            }
        }
        if mood == .boil {
            for k in 0..<3 {
                let puff = CALayer()
                puff.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
                puff.cornerRadius = 6
                puff.backgroundColor = NSColor(white: 0.8, alpha: 1).cgColor
                puff.position = CGPoint(x: ox + p.cx - 14 + CGFloat(k) * 14, y: oy + p.y0 - p.ic - 6)
                puff.opacity = 0
                let rise = basic("transform.translation.y", 0, -14, 1.4, .easeOut, reverse: false)
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 0.6, 0]; fade.keyTimes = [0, 0.3, 1]; fade.duration = 1.4
                let both = CAAnimationGroup(); both.animations = [rise, fade]; both.duration = 1.4
                puff.add(loop(both, delay: Double(k) * 0.45), forKey: "steam")
                breathe.addSublayer(puff)
            }
        }
        if mood == .sleep {
            let (_, gap, cy) = p.eye
            for (i, base) in [CGPoint(x: p.cx + gap + 10, y: cy - 14), CGPoint(x: p.cx + gap + 18, y: cy - 24)].enumerated() {
                let z = CATextLayer()
                z.string = "z"
                z.font = NSFont.systemFont(ofSize: 12)
                z.fontSize = 12
                z.foregroundColor = NSColor(white: 0.6, alpha: 1).cgColor   // 라이트·다크 어디서나 읽히는 회색(다시 굽지 않아도 되게)
                z.contentsScale = scale
                z.anchorPoint = CGPoint(x: 0, y: 1)
                z.bounds = CGRect(x: 0, y: 0, width: 10, height: 15)
                z.position = CGPoint(x: ox + base.x, y: oy + base.y + 3)
                z.opacity = 0
                let drift = CABasicAnimation(keyPath: "transform.translation")
                drift.fromValue = NSValue(size: CGSize(width: 0, height: 4))
                drift.toValue = NSValue(size: CGSize(width: 6, height: -10))
                drift.duration = 2.4
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 0]; fade.keyTimes = [0, 0.5, 1]; fade.duration = 2.4
                let both = CAAnimationGroup(); both.animations = [drift, fade]; both.duration = 2.4
                z.add(loop(both, delay: Double(i) * 0.8), forKey: "zz")
                breathe.addSublayer(z)
            }
        }
    }
}

/// 시안(맨 처음 블롭 시안)의 SVG 를 그대로 옮긴 그리기.
struct BlobPainter {
    let cpu: Double
    let m: BlobMetrics

    static let ink = Color(red: 0.114, green: 0.114, blue: 0.122)
    static let sweat = Color(red: 0.486, green: 0.784, blue: 1)
    static let blush = Color(red: 1, green: 0.42, blue: 0.541)

    var mood: CPUMood { CPUMood(cpu: cpu) }
    /// 숨쉬기 한 번(초). 바쁠수록 빠르다.
    var period: Double { max(0.35, 3.2 - cpu / 35) }
    var hasEffects: Bool { mood == .sleep || mood == .sweat || mood == .boil }
    // 자주 쓰는 자리
    var h: CGFloat { m.height }
    var x0: CGFloat { 8 }
    var y0: CGFloat { m.height - m.H }
    var cx: CGFloat { m.width / 2 }
    var ic: CGFloat { 16 + m.s * 10 }
    var eye: (e: CGFloat, gap: CGFloat, cy: CGFloat) { (4 + m.s * 3, 10 + m.s * 12, y0 + m.H * 0.42) }

    /// 움직이지 않는 부분: 그림자, 몸, 반짝임, 모자, 얼굴
    func drawBody(_ ctx: inout GraphicsContext, icon: GraphicsContext.ResolvedImage) {
        let (W, H) = (m.W, m.H)

        // 그림자
        ctx.fill(Path(ellipseIn: CGRect(x: cx - W / 2, y: h - 7, width: W, height: 10)), with: .color(.black.opacity(0.12)))

        // 몸
        var body = Path()
        body.move(to: CGPoint(x: x0, y: h))
        body.addCurve(to: CGPoint(x: cx, y: y0), control1: CGPoint(x: x0 - 4, y: y0 + H * 0.25), control2: CGPoint(x: x0 + W * 0.18, y: y0))
        body.addCurve(to: CGPoint(x: x0 + W, y: h), control1: CGPoint(x: x0 + W * 0.82, y: y0), control2: CGPoint(x: x0 + W + 4, y: y0 + H * 0.25))
        body.closeSubpath()
        ctx.fill(body, with: .color(Palette.tint(cpu)))

        // 윗부분 반짝임
        var shine = Path()
        let p0 = CGPoint(x: x0 + W * 0.2, y: y0 + H * 0.3)
        shine.move(to: p0)
        shine.addQuadCurve(to: CGPoint(x: p0.x + W * 0.25, y: p0.y - H * 0.2), control: CGPoint(x: p0.x + W * 0.1, y: p0.y - H * 0.18))
        ctx.stroke(shine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        // 앱 아이콘 모자 (-8도 기울임)
        var hat = ctx
        hat.translateBy(x: cx, y: y0)
        hat.rotate(by: .degrees(-8))
        hat.draw(icon, in: CGRect(x: -ic * 0.6, y: -ic * 0.62 - ic * 0.1, width: ic * 1.2, height: ic * 1.2))

        drawFace(&ctx, mood: mood)
    }

    /// 매 프레임 바뀌는 부분: 땀방울, 김, zz
    func drawEffects(_ ctx: inout GraphicsContext, time: TimeInterval) {
        let (W, H) = (m.W, m.H)
        if mood == .sweat || mood == .boil {
            drop(&ctx, time: time, x: x0 + W - 6, y: y0 + H * 0.25, phase: 0)
            drop(&ctx, time: time, x: x0 + 6, y: y0 + H * 0.35, phase: 0.5)
        }
        if mood == .boil {
            for k in 0..<3 {
                let p = cycle(time, 1.4, delay: Double(k) * 0.45)
                let eased = 1 - (1 - p) * (1 - p)
                let a = p < 0.3 ? p / 0.3 * 0.6 : 0.6 * (1 - (p - 0.3) / 0.7)
                let c = CGPoint(x: cx - 14 + CGFloat(k) * 14, y: y0 - ic - 6 - 14 * eased)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Color(white: 0.8).opacity(a)))
            }
        }
        if mood == .sleep {
            let (_, gap, cy) = eye
            for (i, base) in [CGPoint(x: cx + gap + 10, y: cy - 14), CGPoint(x: cx + gap + 18, y: cy - 24)].enumerated() {
                let q = cycle(time, 2.4, delay: Double(i) * 0.8)
                let a = q < 0.5 ? q * 2 : 2 - q * 2
                let pt = CGPoint(x: base.x + 6 * q, y: base.y + 4 - 14 * q)
                ctx.draw(Text("z").font(.system(size: 12)).foregroundColor(Color(white: 0.6).opacity(a)), at: pt, anchor: .bottomLeading)
            }
        }
    }

    /// 0…1 로 도는 진행값
    func cycle(_ time: TimeInterval, _ period: Double, delay: Double) -> Double {
        let v = (time - delay).truncatingRemainder(dividingBy: period) / period
        return v < 0 ? v + 1 : v
    }

    func drop(_ ctx: inout GraphicsContext, time: TimeInterval, x: CGFloat, y: CGFloat, phase: Double) {
        let p = cycle(time, 1.1, delay: phase)
        let a = p < 0.2 ? p / 0.2 : 1 - (p - 0.2) / 0.8
        let dy = -4 + 20 * p * p   // ease-in
        var d = Path()
        d.move(to: CGPoint(x: x, y: y + dy))
        d.addQuadCurve(to: CGPoint(x: x, y: y + dy + 10), control: CGPoint(x: x + 4, y: y + dy + 7))
        d.addQuadCurve(to: CGPoint(x: x, y: y + dy), control: CGPoint(x: x - 4, y: y + dy + 7))
        ctx.fill(d, with: .color(Self.sweat.opacity(a)))
    }

    func drawFace(_ ctx: inout GraphicsContext, mood: CPUMood) {
        let (e, gap, cy) = eye
        let s = m.s
        let line = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        switch mood {
        case .sleep:
            var p = Path()
            for x in [cx - gap - e, cx + gap - e] {
                p.move(to: CGPoint(x: x, y: cy))
                p.addQuadCurve(to: CGPoint(x: x + 2 * e, y: cy), control: CGPoint(x: x + e, y: cy + e))
            }
            ctx.stroke(p, with: .color(Self.ink), style: line(2.2))
        case .sweat, .boil:
            var p = Path()
            p.move(to: CGPoint(x: cx - gap - e, y: cy - e)); p.addLine(to: CGPoint(x: cx - gap + 0.6 * e, y: cy)); p.addLine(to: CGPoint(x: cx - gap - e, y: cy + e))
            p.move(to: CGPoint(x: cx + gap + e, y: cy - e)); p.addLine(to: CGPoint(x: cx + gap - 0.6 * e, y: cy)); p.addLine(to: CGPoint(x: cx + gap + e, y: cy + e))
            ctx.stroke(p, with: .color(Self.ink), style: line(2.4))
            let rx = 4 + s * 4, ry = 3 + s * 3
            ctx.fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy + e + 8 - ry, width: rx * 2, height: ry * 2)), with: .color(Self.ink))
            let crx = 5 + s * 3
            for x in [cx - gap - e - 6, cx + gap + e + 6] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - crx, y: cy + e + 1, width: crx * 2, height: 6)), with: .color(Self.blush.opacity(0.55)))
            }
        case .happy, .busy:
            for x in [cx - gap, cx + gap] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - e, y: cy - e, width: e * 2, height: e * 2)), with: .color(Self.ink))
                let r = e * 0.35
                ctx.fill(Path(ellipseIn: CGRect(x: x + r - r, y: cy - r - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
            var mouth = Path()
            if mood == .happy {
                mouth.move(to: CGPoint(x: cx - 6, y: cy + e + 5))
                mouth.addQuadCurve(to: CGPoint(x: cx + 6, y: cy + e + 5), control: CGPoint(x: cx, y: cy + e + 11))
            } else {
                mouth.move(to: CGPoint(x: cx - 6, y: cy + e + 7)); mouth.addLine(to: CGPoint(x: cx + 6, y: cy + e + 7))
            }
            ctx.stroke(mouth, with: .color(Self.ink), style: line(2.2))
        }
    }
}

/// 오른쪽 상세 칸
struct AppDetail: View {
    let group: AppGroup
    /// 종료 확인창이 떠 있는 동안은 종료 버튼을 다시 누를 수 없게
    var busy = false
    var ask: () -> Void

    var body: some View {
        let quittable = canQuit(group, selfPID: Int(getpid()), selfBundle: Bundle.main.bundlePath.hasSuffix(".app") ? Bundle.main.bundlePath : nil)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.nsImage(for: group)).resizable().frame(width: 26, height: 26)
                Text(group.name).font(.system(size: 16, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            }
            Text(group.mood.text).font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 4)
            Text(String(format: "%.1f%%", group.cpu)).font(.system(size: 30, weight: .bold)).foregroundStyle(Palette.tint(group.cpu))
            Text("CPU · 코어 하나가 100%").font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row("메모리", String(format: "%.1f%%", group.mem))
                row("합친 프로세스", "\(group.procs.count)개")
                row("실행 시간", describeElapsed(group.elapsedSeconds))
            }
            .font(.system(size: 13)).padding(.vertical, 6)
            HStack(spacing: 6) {
                if quittable {
                    Button(group.name.count <= 10 ? "\(group.name) 종료…" : "종료…", role: .destructive, action: ask)
                        .buttonStyle(DangerButtonStyle()).disabled(busy).opacity(busy ? 0.5 : 1)
                }
                if let path = group.appPath ?? (group.procs.first.map(\.path).flatMap { $0.hasPrefix("/") ? $0 : nil }) {
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
            }
            .padding(.top, 8)
            Text(hint(quittable)).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func hint(_ quittable: Bool) -> String {
        if !quittable {
            return group.pids.contains(Int(getpid())) ? "Backstage 자신이에요. 끄려면 메뉴바에서 종료하세요." : "macOS 기본 프로그램이라 여기서는 끄지 않아요."
        }
        return group.appPath != nil
            ? "종료를 누르면 앱에 꺼 달라고 요청해요. 저장 안 한 게 있으면 앱이 물어봐요."
            : "종료 신호(SIGTERM)를 보내요. 프로그램이 스스로 정리하고 꺼져요."
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
            .padding(.vertical, 3)
            .overlay(alignment: .bottom) {
                Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 1000, y: 0)) }
                    .stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).clipped()
            }
    }
}

// MARK: - 종료 확인

struct QuitFlow: Identifiable {
    enum Step: Equatable { case confirm, waiting(Int), stuck, done }
    let group: AppGroup
    var step: Step = .confirm
    let token = UUID()
    var id: UUID { token }
}

/// 확인 → 정상 종료 요청 → 5초 안에 안 꺼지면 강제 종료를 고를 수 있게.
struct QuitSheet: View {
    @State var flow: QuitFlow
    var close: () -> Void
    @ObservedObject var store: Store

    var body: some View {
        let g = flow.group
        ZStack(alignment: .top) {
            Color.black.opacity(0.28).contentShape(Rectangle()).onTapGesture { if flow.step != .confirm { close() } }
            VStack(spacing: 8) {
                switch flow.step {
                case .confirm:
                    Text("\(withJosa(g.name, isApp: g.appPath != nil, "을", "를")) 끌까요?").font(.system(size: 14, weight: .bold))
                    Text("CPU \(String(format: "%.1f", g.cpu))% · 프로세스 \(g.procs.count)개\n"
                         + (g.appPath != nil ? "저장하지 않은 문서가 있으면 앱이 물어봐요." : "프로그램에 종료 신호를 보내요."))
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    buttons {
                        Button("취소", action: close).keyboardShortcut(.cancelAction)
                        Button("종료", role: .destructive) { start() }.buttonStyle(DangerButtonStyle())
                    }
                case .waiting(let n):
                    Text("\(g.name)에 종료를 요청했어요").font(.system(size: 14, weight: .bold))
                    Text("꺼지기를 기다리는 중… \(n)").font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                    buttons { Button("닫기", action: close).keyboardShortcut(.cancelAction) }
                case .stuck:
                    Text("\(withJosa(g.name, isApp: g.appPath != nil, "이", "가")) 아직 안 꺼졌어요").font(.system(size: 14, weight: .bold))
                    Text((g.appPath != nil ? "저장할지 묻는 창이 떠 있을 수 있어요. 앱으로 가서 확인해 보세요.\n" : "응답이 없을 수 있어요.\n")
                         + "강제 종료하면 저장 안 한 작업은 사라져요.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    buttons {
                        Button("닫기", action: close).keyboardShortcut(.cancelAction)
                        if let app = Quitter.runningApp(g) {
                            Button("앱으로 가기") { app.activate(); close() }
                        }
                        Button("강제 종료", role: .destructive) { force() }.buttonStyle(DangerButtonStyle())
                    }
                case .done:
                    Text("\(withJosa(g.name, isApp: g.appPath != nil, "을", "를")) 껐어요").font(.system(size: 14, weight: .bold))
                }
            }
            .padding(18)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface).shadow(color: .black.opacity(0.35), radius: 25, y: 20))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .padding(.top, 40).padding(.horizontal, 16)
        }
        // 화면을 못 보는 사람도 단계가 바뀐 걸 알 수 있게(초 세기는 읽지 않는다)
        .onChange(of: flow.step) { _, step in
            let text: String? = switch step {
            case .stuck: "\(withJosa(g.name, isApp: g.appPath != nil, "이", "가")) 아직 안 꺼졌어요. 강제 종료할 수 있어요."
            case .done: "\(withJosa(g.name, isApp: g.appPath != nil, "을", "를")) 껐어요."
            default: nil
            }
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
    }

    func buttons<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) { Spacer(); c() }.padding(.top, 6)
    }

    func start() {
        let g = flow.group
        if store.demo { store.pretendQuit(g); flow.step = .done; Task { @MainActor in try? await Task.sleep(for: .seconds(1.2)); close() }; return }
        Quitter.requestQuit(g)
        flow.step = .waiting(Quitter.grace)
        Task { @MainActor in
            for left in stride(from: Quitter.grace - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard case .waiting = flow.step else { return }   // 닫혔거나 넘어감
                if Quitter.alive(g).isEmpty { finished(); return }
                flow.step = left > 0 ? .waiting(left) : .stuck
            }
        }
    }

    func force() {
        let g = flow.group
        Quitter.forceQuit(g)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if Quitter.alive(g).isEmpty { finished() } else { flow.step = .stuck; store.refresh() }
        }
    }

    /// 꺼졌다고 잠깐 알려 주고 닫는다
    func finished() {
        flow.step = .done
        store.refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            close()
        }
    }
}

/// 빨간 바탕의 종료 버튼(시안의 danger 버튼)
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.hot.opacity(configuration.isPressed ? 0.75 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - 색과 아이콘

enum Palette {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    static let window = dynamic(hex(0xf6f6f8), hex(0x1e1e21))
    static let surface = dynamic(hex(0xffffff), hex(0x2a2a2e))
    static let line = dynamic(hex(0xd9d8de), hex(0x3a3a3f))
    static let floor = dynamic(hex(0xe4e2ea), hex(0x26252b))
    static let ok = Color(nsColor: hex(0x34c759))
    static let warm = Color(nsColor: hex(0xff9f0a))
    static let hot = Color(nsColor: hex(0xff453a))

    /// 초록 → 주황 → 빨강. 80% 에서 빨강이 된다.
    static func tint(_ cpu: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(52, 199, 89), (255, 159, 10), (255, 69, 58)]
        let t = min(1, max(0, cpu / 80)) * 2
        let i = min(1, Int(t)), f = t - Double(i)
        let a = stops[i], b = stops[min(2, i + 1)]
        return Color(red: (a.0 + (b.0 - a.0) * f) / 255, green: (a.1 + (b.1 - a.1) * f) / 255, blue: (a.2 + (b.2 - a.2) * f) / 255)
    }
}

/// 앱이면 실제 아이콘, 아니면(또는 예시 데이터라 파일이 없으면) 이름 첫 글자 타일.
enum AppIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func nsImage(for g: AppGroup) -> NSImage {
        if let hit = cache[g.id] { return hit }
        let img: NSImage
        if let app = g.appPath, FileManager.default.fileExists(atPath: app) {
            img = NSWorkspace.shared.icon(forFile: app)
        } else {
            img = letterTile(g.name)
        }
        cache[g.id] = img
        return img
    }

    @MainActor static func image(for g: AppGroup) -> Image { Image(nsImage: nsImage(for: g)) }

    static func letterTile(_ name: String) -> NSImage {
        let colors: [UInt32] = [0x4285f4, 0x1d63ed, 0x611f69, 0xa259ff, 0x1db954, 0x3a3a3c, 0xff6363, 0x0572ec]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        let fill = Palette.hex(colors[hash % colors.count])
        let letter = String(name.first(where: \.isLetter) ?? "?").uppercased()
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            let tile = r.insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: tile, xRadius: 13, yRadius: 13)
            fill.setFill(); path.fill()
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white]
            let s = NSAttributedString(string: letter, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
            return true
        }
    }
}
