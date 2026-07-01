import SwiftUI

// マイクレベルに反応するアニメーション波形
struct WaveformView: View {
    var level: CGFloat
    var active: Bool = true
    private let barCount = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let barWidth: CGFloat = 3
                let gap = (size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)
                let midY = size.height / 2

                for i in 0..<barCount {
                    let phase = Double(i) * 0.48
                    let wobble = 0.55
                        + 0.28 * sin(t * 8.2 + phase)
                        + 0.17 * sin(t * 5.1 + phase * 1.9)
                    let amplitude = active ? max(0.06, level) : 0.05
                    let h = max(3, size.height * amplitude * CGFloat(wobble))
                    let x = CGFloat(i) * (barWidth + gap)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                    let progress = Double(i) / Double(barCount - 1)
                    let color = Color(
                        hue: 0.72 - progress * 0.1,
                        saturation: 0.75,
                        brightness: active ? 1.0 : 0.6
                    )
                    context.fill(path, with: .color(color.opacity(active ? 0.95 : 0.4)))
                }
            }
        }
    }
}
