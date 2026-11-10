// Génère l'icône de Vigie (PNG 1024×1024) avec CoreGraphics, sans aucun outil externe.
// Usage : swiftc -O icon/make_icon.swift -o /tmp/make_icon && /tmp/make_icon sortie.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("contexte graphique impossible") }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Forme « squircle » d'icône macOS (superellipse), 824 pt dans un cadre de 1024 pt.
func squircle(in r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + (r.width / 2) * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + (r.height / 2) * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(in: box)
let center = CGPoint(x: size / 2, y: size / 2)

// Ombre portée sous l'icône
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x0B2540)); ctx.fillPath()
ctx.restoreGState()

// Tout le dessin est découpé dans la forme
ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// Fond : dégradé bleu nuit -> bleu-vert
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0x0A2342), rgb(0x0B4A6B), rgb(0x0E8A9A)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 180, y: 940), end: CGPoint(x: 860, y: 90), options: [])

// Halo central
let halo = CGGradient(colorsSpace: space,
                      colors: [rgb(0x39D5E0, 0.42), rgb(0x39D5E0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: 400, options: [])

// Anneaux de radar
let rings: [(CGFloat, CGFloat)] = [(320, 0.50), (232, 0.40), (144, 0.34), (58, 0.30)]
for (r, a) in rings {
    ctx.setStrokeColor(rgb(0xBFF3F7, a)); ctx.setLineWidth(9)
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
}
// Axes
ctx.setStrokeColor(rgb(0xBFF3F7, 0.22)); ctx.setLineWidth(6)
ctx.move(to: CGPoint(x: center.x - 330, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + 330, y: center.y))
ctx.move(to: CGPoint(x: center.x, y: center.y - 330)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 330))
ctx.strokePath()

// Faisceau du balayage : traînée dégradée, de l'angle 20° (tête) vers l'arrière
let headAngle: CGFloat = 38 * .pi / 180
let trail: CGFloat = 105 * .pi / 180
let slices = 120
for i in 0..<slices {
    let f = CGFloat(i) / CGFloat(slices)            // 0 = tête
    let a0 = headAngle - f * trail
    let a1 = headAngle - (f + 1 / CGFloat(slices)) * trail
    let alpha = pow(1 - f, 2.2) * 0.62
    ctx.setFillColor(rgb(0x6CF2F5, alpha))
    ctx.move(to: center)
    ctx.addArc(center: center, radius: 322, startAngle: a0, endAngle: a1 - 0.002, clockwise: true)
    ctx.closePath(); ctx.fillPath()
}
// Ligne de tête du faisceau
ctx.setStrokeColor(rgb(0xE8FEFF, 0.95)); ctx.setLineWidth(11); ctx.setLineCap(.round)
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x + 322 * cos(headAngle), y: center.y + 322 * sin(headAngle)))
ctx.strokePath()

// Points détectés (bois / ambre : clin d'œil à Woodstyles) avec lueur
func blip(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, hot: Bool) {
    let c = CGPoint(x: x, y: y)
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(hot ? 0xFFB347 : 0x9FF3F7, 0.75), rgb(hot ? 0xFFB347 : 0x9FF3F7, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 3.2, options: [])
    ctx.setFillColor(rgb(hot ? 0xFFC46B : 0xE8FEFF)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}
blip(center.x + 205, center.y + 150, 25, hot: true)
blip(center.x - 120, center.y + 205, 17, hot: false)
blip(center.x + 120, center.y - 215, 19, hot: false)
blip(center.x - 215, center.y - 70, 14, hot: false)

// Centre
ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))
ctx.setFillColor(rgb(0x0B4A6B)); ctx.fillEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))

// Reflet doux en haut
let gloss = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.09), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
ctx.restoreGState()

// Liseré intérieur fin
ctx.addPath(shape); ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(3); ctx.strokePath()

guard let img = ctx.makeImage() else { fatalError("image impossible") }
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("Icône écrite : \(outPath)")
