import SwiftUI
import UIKit

struct AppBackdrop: View {
    let imageData: Data?
    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill().overlay(.black.opacity(0.15))
            } else {
                LinearGradient(colors: [.blue.opacity(0.08), .mint.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

extension View {
    /// 与补丁中的根视图调用保持一致；背景图片由环境中的 LedgerStore 提供。
    func appBackdrop() -> some View { modifier(AppBackdropModifier()) }
}

private struct AppBackdropModifier: ViewModifier {
    @EnvironmentObject private var store: LedgerStore
    func body(content: Content) -> some View { ZStack { AppBackdrop(imageData: store.backgroundImageData); content } }
}
