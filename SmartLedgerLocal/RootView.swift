import SwiftUI
import UIKit

enum AppTab: Hashable { case dashboard, books, transactions, add, more }
struct RootView: View {
    @EnvironmentObject private var store: LedgerStore; @State private var tab: AppTab = .dashboard
    var body: some View {
        ZStack { if let data = store.backgroundImageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea().overlay(.black.opacity(0.15)).accessibilityHidden(true) }; TabView(selection: $tab) {
            NavigationStack { DashboardView() }.tabItem { Label("概览", systemImage: "chart.bar.fill") }.tag(AppTab.dashboard)
            NavigationStack { BooksView() }.tabItem { Label("账本", systemImage: "books.vertical.fill") }.tag(AppTab.books)
            NavigationStack { TransactionsView() }.tabItem { Label("流水", systemImage: "list.bullet.rectangle") }.tag(AppTab.transactions)
            NavigationStack { CreateTransactionView() }.tabItem { Label("记账", systemImage: "plus.circle.fill") }.tag(AppTab.add)
            NavigationStack { MoreView() }.tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }.tag(AppTab.more)
        }.tint(.blue).background(.clear)
        }
    }
}

struct GlassCard<Content: View>: View { @ViewBuilder let content: Content
    var body: some View { content.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25))) }
}
struct FilterChip: View { let title: String; let selected: Bool
    var body: some View { Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 15).padding(.vertical, 8).background(selected ? Color.blue.opacity(0.17) : Color.primary.opacity(0.07), in: Capsule()).foregroundStyle(selected ? .blue : .primary) }
}
struct EmptyState: View { let title: String; let systemImage: String
    var body: some View { ContentUnavailableView(title, systemImage: systemImage) }
}
