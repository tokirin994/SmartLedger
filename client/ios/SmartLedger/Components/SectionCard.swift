import SwiftUI

struct SectionCard<Content: View, HeaderTrailing: View>: View {
    let title: String
    let subtitle: String?
    let showSubtitle: Bool
    let headerTrailing: (() -> AnyView)?
    @ViewBuilder let content: () -> Content
    let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    // MARK: 主初始化器
    init(title: String,
         subtitle: String? = nil,
         showSubtitle: Bool = false,
         headerTrailing: (() -> AnyView)? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder headerTrailing: () -> HeaderTrailing,
         @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showSubtitle = showSubtitle
        self.headerTrailing = headerTrailing()
        self.content = content()
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部: 标题 + 可选副标题 + 右侧自定义视图
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline.weight(.semibold))

                            if showSubtitle, let subtitle {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)

                        headerTrailing
                    }
                }

                // 分隔线
                Rectangle()
                    .fill(.separator.opacity(0.6))
                    .frame(height: 0.5)

                // 主体内容
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24, strokeOpacity: 0.30)
        .shadow(color: .black.opacity(0.035), radius: 14, x: 0, y: 8)
    }
}


