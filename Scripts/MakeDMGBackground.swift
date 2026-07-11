// DMG インストーラーウィンドウの背景画像生成スクリプト
// 使い方: swift Scripts/MakeDMGBackground.swift <出力ディレクトリ>
// dmg-background.png(1x)と dmg-background@2x.png(2x)を書き出し、
// make-dmg.sh が tiffutil で Retina 対応 TIFF に合成して DMG に封入する。
//
// 座標は make-dmg.sh の Finder アイコン配置と対応している(ずらすときは両方直す):
//   ウィンドウ内容領域 660x400 / Youyaku.app {165,190} / Applications {495,190}(左上原点・アイコン中心)
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist"

let W: CGFloat = 660
let H: CGFloat = 400
// Finder の座標は左上原点、AppKit の描画は左下原点なので y は反転して使う
let appCenter = NSPoint(x: 165, y: H - 190) // Youyaku.app のアイコン中心
let dstCenter = NSPoint(x: 495, y: H - 190) // Applications のアイコン中心

// アプリアイコン(MakeIcon.swift)と同じブランドカラー
let brandA = NSColor(calibratedRed: 0.43, green: 0.36, blue: 1.00, alpha: 1)
let brandB = NSColor(calibratedRed: 0.71, green: 0.30, blue: 1.00, alpha: 1)

func drawCentered(_ text: String, center: NSPoint, font: NSFont, color: NSColor) {
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = s.size()
    s.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
}

func drawBackground(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 以降はポイント座標で描く(2x はここで一括拡大)
    let t = NSAffineTransform()
    t.scale(by: scale)
    t.concat()

    // ベース: 白 → ごく薄いラベンダーの縦グラデーション
    let full = NSRect(x: 0, y: 0, width: W, height: H)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.98, alpha: 1),
    ])!.draw(in: full, angle: -90)

    // アイコンの置き場所を示す淡い円形の「受け皿」
    for center in [appCenter, dstCenter] {
        let r: CGFloat = 82
        let pad = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
        pad.fill()
        NSColor(calibratedRed: 0.43, green: 0.36, blue: 1.00, alpha: 0.12).setStroke()
        pad.lineWidth = 1.5
        pad.stroke()
    }

    // 中央の矢印(軸 + 三角の頭)をひとつのパスにして、ブランドカラーで塗る
    let arrowY = appCenter.y
    let shaftLeft: CGFloat = 268
    let headBack: CGFloat = 372
    let headTip: CGFloat = 404
    let shaftHalf: CGFloat = 7
    let headHalf: CGFloat = 20
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: shaftLeft, y: arrowY + shaftHalf))
    arrow.line(to: NSPoint(x: headBack, y: arrowY + shaftHalf))
    arrow.line(to: NSPoint(x: headBack, y: arrowY + headHalf))
    arrow.line(to: NSPoint(x: headTip, y: arrowY))
    arrow.line(to: NSPoint(x: headBack, y: arrowY - headHalf))
    arrow.line(to: NSPoint(x: headBack, y: arrowY - shaftHalf))
    arrow.line(to: NSPoint(x: shaftLeft, y: arrowY - shaftHalf))
    arrow.close()
    arrow.lineJoinStyle = .round
    NSGradient(colors: [brandA.withAlphaComponent(0.85), brandB.withAlphaComponent(0.85)])!
        .draw(in: arrow, angle: 0)

    // 上部にワードマーク、下部に一言だけ説明
    drawCentered("Youyaku", center: NSPoint(x: W / 2, y: H - 46),
                 font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                 color: NSColor(calibratedRed: 0.29, green: 0.27, blue: 0.36, alpha: 1))
    drawCentered("ドラッグしてインストール", center: NSPoint(x: W / 2, y: 44),
                 font: NSFont.systemFont(ofSize: 13, weight: .medium),
                 color: NSColor(calibratedRed: 0.58, green: 0.57, blue: 0.65, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()
    // PNG の DPI メタデータ用にポイントサイズを付ける(描画後に設定して二重スケールを避ける)
    rep.size = NSSize(width: W, height: H)
    return rep
}

for (name, scale) in [("dmg-background", CGFloat(1)), ("dmg-background@2x", CGFloat(2))] {
    let rep = drawBackground(scale: scale)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 変換に失敗")
    }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("DMG 背景画像を書き出しました: \(outDir)/dmg-background.png, \(outDir)/dmg-background@2x.png")
