// 앱 아이콘(1024px PNG)을 그린다: 밝은 무대에 선 큰 캐릭터 하나(프로그램 탭의 블롭과 같은 곡선), 머리에 시계 모자
// swift tools/make_icon.swift <출력.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a).cgColor
}

// macOS 아이콘 격자: 1024 캔버스 안 824 둥근 사각형
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 그림자
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// 배경: 연보라 → 흰색, 아래는 바닥 띠
let bg = CGGradient(colorsSpace: nil, colors: [rgb(0xE9E4F7), rgb(0xFFFFFF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
ctx.setFillColor(rgb(0xD9D3EA)); ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 170))

// 캐릭터. 앱의 BlobPainter 와 같은 곡선을 y 가 위로 가는 좌표로 옮겼다. k 는 앱(폭 162) 대비 배율.
let W: CGFloat = 560, H: CGFloat = 480, k = W / 162
let b = CGPoint(x: 512, y: 250)            // 바닥 가운데
let x0 = b.x - W / 2, top = b.y + H
let ink = rgb(0x1D1D1F)

ctx.setFillColor(rgb(0x000000, 0.18))
ctx.fillEllipse(in: CGRect(x: b.x - W / 2, y: b.y - 14 * k, width: W, height: 20 * k))

let body = CGMutablePath()
body.move(to: CGPoint(x: x0, y: b.y))
body.addCurve(to: CGPoint(x: b.x, y: top), control1: CGPoint(x: x0 - 4 * k, y: top - H * 0.25), control2: CGPoint(x: x0 + W * 0.18, y: top))
body.addCurve(to: CGPoint(x: x0 + W, y: b.y), control1: CGPoint(x: x0 + W * 0.82, y: top), control2: CGPoint(x: x0 + W + 4 * k, y: top - H * 0.25))
body.closeSubpath()
ctx.addPath(body); ctx.setFillColor(rgb(0x70BD5C)); ctx.fillPath()

// 반짝임
let s0 = CGPoint(x: x0 + W * 0.2, y: top - H * 0.3)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.38)); ctx.setLineWidth(5 * k); ctx.setLineCap(.round)
ctx.move(to: s0)
ctx.addQuadCurve(to: CGPoint(x: s0.x + W * 0.25, y: s0.y + H * 0.2), control: CGPoint(x: s0.x + W * 0.1, y: s0.y + H * 0.18))
ctx.strokePath()

// 얼굴: 한가한(happy) 표정
let e = 7 * k, gap = 22 * k, cy = top - H * 0.42
for x in [b.x - gap, b.x + gap] {
    ctx.setFillColor(ink); ctx.fillEllipse(in: CGRect(x: x - e, y: cy - e, width: 2 * e, height: 2 * e))
    let r = e * 0.35
    ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: x, y: cy, width: 2 * r, height: 2 * r))
}
ctx.setStrokeColor(ink); ctx.setLineWidth(3 * k)
ctx.move(to: CGPoint(x: b.x - 7 * k, y: cy - e - 6 * k))
ctx.addQuadCurve(to: CGPoint(x: b.x + 7 * k, y: cy - e - 6 * k), control: CGPoint(x: b.x, y: cy - e - 13 * k))
ctx.strokePath()

// 모자: 메뉴바와 같은 시계 기호를 남색 타일에, 앱 캐릭터의 아이콘 모자처럼 기울여
let ic = 30 * k
ctx.saveGState()
ctx.translateBy(x: b.x, y: top)
ctx.rotate(by: 8 * .pi / 180)
let tile = CGRect(x: -ic * 0.6, y: -ic * 0.2, width: ic * 1.2, height: ic * 1.2)
ctx.setShadow(offset: CGSize(width: 0, height: -3 * k), blur: 6 * k, color: rgb(0x000000, 0.25))
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: ic * 0.28, cornerHeight: ic * 0.28, transform: nil))
ctx.setFillColor(rgb(0x2E2450)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0)
let conf = NSImage.SymbolConfiguration(pointSize: ic * 0.72, weight: .bold)
    .applying(.init(paletteColors: [NSColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 1)]))
if let sym = NSImage(systemSymbolName: "clock.arrow.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(conf) {
    let s = sym.size
    sym.draw(in: CGRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height))
}
ctx.restoreGState()

ctx.restoreGState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("저장: \(out)")
