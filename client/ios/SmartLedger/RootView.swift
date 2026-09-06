import SwiftUI

enum AppTab: Hashable { case dashboard, books, transactions, add, more }
struct RootView: View {
    @EnvironmentObject private var store: LedgerStore; @State private var tab: AppTab = .dashboard; @State private var dashboardPath = NavigationPath(); @State private var booksPath = NavigationPath(); @State private var transactionsPath = NavigationPath(); @State private var addPath = NavigationPath(); @State private var morePath = NavigationPath()
    var body: some View {
        ZStack { AppBackdrop(imageData: store.backgroundImageData); TabView(selection: $tab) {
            NavigationStack(path: $dashboardPath) { DashboardView() }.tabItem { Label("概览", systemImage: "chart.bar.fill") }.tag(AppTab.dashboard)
            NavigationStack(path: $booksPath) { BooksView() }.tabItem { Label("账本", systemImage: "books.vertical.fill") }.tag(AppTab.books)
            NavigationStack(path: $transactionsPath) { TransactionsView() }.tabItem { Label("流水", systemImage: "list.bullet.rectangle") }.tag(AppTab.transactions)
            NavigationStack(path: $addPath) { CreateTransactionView() }.tabItem { Label("记账", systemImage: "plus.circle.fill") }.tag(AppTab.add)
            NavigationStack(path: $morePath) { MoreView() }.tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }.tag(AppTab.more)
        }.tint(.blue).background(.clear).onChange(of: tab) { _, newValue in resetPath(for: newValue) }
        }
    }
    private func resetPath(for tab: AppTab) { switch tab { case .dashboard: dashboardPath = NavigationPath(); case .books: booksPath = NavigationPath(); case .transactions: transactionsPath = NavigationPath(); case .add: addPath = NavigationPath(); case .more: morePath = NavigationPath() } }
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
