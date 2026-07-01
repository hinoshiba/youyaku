// アプリアイコン生成スクリプト
// 使い方: swift Scripts/MakeIcon.swift <出力ディレクトリ>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist"

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(size)
    // macOS HIG のグリッドに合わせた余白付き角丸スクエア
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.43, green: 0.36, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.71, green: 0.30, blue: 1.00, alpha: 1),
    ])!
    gradient.draw(in: squircle, angle: -60)

    // 上部ハイライト
    let highlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.18),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])!
    highlight.draw(in: squircle, angle: -90)

    // 波形バー
    let heights: [CGFloat] = [0.26, 0.46, 0.68, 0.50, 0.30]
    let barWidth = rect.width * 0.075
    let gap = rect.width * 0.058
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = rect.midX - totalWidth / 2

    // バーのソフトシャドウ
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.25)
    shadow.shadowBlurRadius = s * 0.012
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
    shadow.set()

    NSColor.white.setFill()
    for h in heights {
        let barHeight = rect.height * h
        let barRect = NSRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
        NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 変換に失敗")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

let iconsetPath = "\(outDir)/Koe.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in entries {
    write(drawIcon(size: size), to: "\(iconsetPath)/\(name).png")
}
print("iconset を書き出しました: \(iconsetPath)")
