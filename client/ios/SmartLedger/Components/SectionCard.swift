import SwiftUI

// MARK: - SectionCard
//
// 通用分组卡片容器：带可选标题、副标题、头部右侧自定义视图（headerTrailing），
// 内容区域由调用方以 ViewBuilder 注入。
// 与 MetricCard 同属 Components 目录下的基础 UI 原子组件。

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let showSubtitle: Bool
    let headerTrailing: (() -> AnyView)?
    @ViewBuilder let content: () -> Content

    // MARK: 主初始化器
    init(
        title: String,
        subtitle: String = "",
        showSubtitle: Bool = false,
        headerTrailing: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showSubtitle = showSubtitle
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：标题 + 可选副标题 + 右侧自定义视图
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))

                    if showSubtitle && !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let headerTrailing {
                    headerTrailing()
                }
            }

            // 分隔线
            Rectangle()
                .fill(.separator.opacity(0.6))
                .frame(height: 0.5)

            // 主体内容
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24, strokeOpacity: 0.30)
        .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Convenience Initializers
extension SectionCard {
    /// 无副标题、无头部右侧视图的简化版本
    init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) where Content: View {
        self.init(
            title: title,
            subtitle: "",
            showSubtitle: false,
            headerTrailing: nil,
            content: content
        )
    }

    /// 带副标题、无头部右侧视图
    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) where Content: View {
        self.init(
            title: title,
            subtitle: subtitle,
            showSubtitle: true,
            headerTrailing: nil,
            content: content
        )
    }
}

#if DEBUG
struct SectionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SectionCard("预算概览") {
                Text("显示预算图表卡片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SectionCard(
                title: "收支日历",
                subtitle: "2026 年 9 月"
            ) {
                Text("点击日期查看当日明细")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
#endif
