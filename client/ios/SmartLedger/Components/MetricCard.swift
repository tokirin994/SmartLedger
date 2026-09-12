import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let showSubtitle: Bool
    let color: Color
    let systemImage: String

    init(title: String, value: String, subtitle: String, showSubtitle: Bool = false, color: Color, systemImage: String) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.showSubtitle = showSubtitle
        self.color = color
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)

                Spacer()

                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(color)
                    }
            }

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            if showSubtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24, strokeOpacity: 0.30)
        .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}
