import SwiftUI

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.padding(16).glassCard() }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeOpacity: Double
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(strokeOpacity), lineWidth: 1) }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22, strokeOpacity: Double = 0.25) -> some View { modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity)) }
}
