import UIKit

// iOS のクリップボード操作(macOS の Paster に相当。他アプリへの自動貼り付けは
// iOS のサンドボックスでは不可能なため、コピーと共有シートを提供する)
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
