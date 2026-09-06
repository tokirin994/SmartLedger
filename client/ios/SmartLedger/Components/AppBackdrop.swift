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
