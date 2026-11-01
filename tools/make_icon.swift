// 앱 아이콘(1024px PNG)을 그린다: 무대 커튼 + 가운데 시계 아이콘
// swift tools/make_icon.swift <출력.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS 아이콘 격자: 1024 캔버스 안 824 둥근 사각형
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 그림자
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// 배경: 어두운 무대
let bg = CGGradient(colorsSpace: nil, colors: [
    NSColor(red: 0.09, green: 0.07, blue: 0.20, alpha: 1).cgColor,
    NSColor(red: 0.20, green: 0.10, blue: 0.36, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])

// 바닥 스포트라이트
let spot = CGGradient(colorsSpace: nil, colors: [
    NSColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.45).cgColor,
    NSColor(red: 1, green: 0.85, blue: 0.55, alpha: 0).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(spot, startCenter: CGPoint(x: size / 2, y: rect.minY + 150), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: rect.minY + 150), endRadius: 360, options: [])

// 커튼: 양옆, 주름은 세로 그라데이션 띠
func curtain(left: Bool) {
    let w: CGFloat = 230
    let x0 = left ? rect.minX : rect.maxX - w
    let path = CGMutablePath()
    if left {
        path.move(to: CGPoint(x: x0, y: rect.minY))
        path.addLine(to: CGPoint(x: x0, y: rect.maxY))
        path.addLine(to: CGPoint(x: x0 + w, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: x0 + 70, y: rect.minY), control: CGPoint(x: x0 + w - 10, y: rect.midY - 40))
    } else {
        path.move(to: CGPoint(x: x0 + w, y: rect.minY))
        path.addLine(to: CGPoint(x: x0 + w, y: rect.maxY))
        path.addLine(to: CGPoint(x: x0, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: x0 + w - 70, y: rect.minY), control: CGPoint(x: x0 + 10, y: rect.midY - 40))
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let folds = 4
    for i in 0..<folds {
        let fw = w / CGFloat(folds)
        let g = CGGradient(colorsSpace: nil, colors: [
            NSColor(red: 0.55, green: 0.05, blue: 0.12, alpha: 1).cgColor,
            NSColor(red: 0.86, green: 0.16, blue: 0.24, alpha: 1).cgColor,
            NSColor(red: 0.55, green: 0.05, blue: 0.12, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.5, 1])!
        let fx = x0 + CGFloat(i) * fw
        ctx.drawLinearGradient(g, start: CGPoint(x: fx, y: 0), end: CGPoint(x: fx + fw, y: 0), options: [])
    }
    ctx.restoreGState()
}
curtain(left: true)
curtain(left: false)

// 위쪽 가림막(밸런스)
let valance = CGRect(x: rect.minX, y: rect.maxY - 120, width: rect.width, height: 120)
let vg = CGGradient(colorsSpace: nil, colors: [
    NSColor(red: 0.62, green: 0.07, blue: 0.15, alpha: 1).cgColor,
    NSColor(red: 0.80, green: 0.14, blue: 0.22, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.saveGState()
let vpath = CGMutablePath()
vpath.addRect(CGRect(x: valance.minX, y: valance.minY + 40, width: valance.width, height: valance.height - 40))
let scallops = 6
let sw = valance.width / CGFloat(scallops)
for i in 0..<scallops {
    vpath.addEllipse(in: CGRect(x: valance.minX + CGFloat(i) * sw, y: valance.minY, width: sw, height: 80))
}
ctx.addPath(vpath); ctx.clip()
ctx.drawLinearGradient(vg, start: CGPoint(x: 0, y: valance.minY), end: CGPoint(x: 0, y: valance.maxY), options: [])
ctx.restoreGState()
// 금색 테두리 선
ctx.setStrokeColor(NSColor(red: 0.98, green: 0.78, blue: 0.35, alpha: 1).cgColor)
ctx.setLineWidth(10)
ctx.move(to: CGPoint(x: rect.minX, y: valance.minY + 44)); ctx.addLine(to: CGPoint(x: rect.maxX, y: valance.minY + 44))
ctx.strokePath()

ctx.restoreGState()

// 가운데: 메뉴바와 같은 시계 아이콘
let conf = NSImage.SymbolConfiguration(pointSize: 330, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)]))
if let sym = NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(conf) {
    let s = sym.size
    let r = CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 30, width: s.width, height: s.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    sym.draw(in: r)
    ctx.restoreGState()
}

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("저장: \(out)")
