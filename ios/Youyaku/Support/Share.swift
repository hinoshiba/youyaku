import SwiftUI
import UIKit

// 共有シート表示用のペイロード(Identifiable な sheet(item:) 用)
struct SharePayload: Identifiable {
    let text: String
    var id: String { text }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
