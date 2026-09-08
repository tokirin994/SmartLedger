import SwiftUI

@main
struct SmartLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(settings.preferredColorScheme)
                .task {
                    await store.bootstrapIfNeeded()
                }
        }
    }
}

private struct RootTabView: View {
    @State private var selection: RootTab = .dashboard
    @State private var dashboardResetToken = UUID()
    @State private var booksResetToken = UUID()
    @State private var transactionsResetToken = UUID()
    @State private var importsResetToken = UUID()
    @State private var moreResetToken = UUID()

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .id(dashboardResetToken)
                .tag(RootTab.dashboard)
                .tabItem {
                    Label("概览", systemImage: "chart.bar.xaxis")
                }
            BooksView()
                .id(booksResetToken)
                .tag(RootTab.books)
                .tabItem {
                    Label("账本", systemImage: "books.vertical")
                }
            TransactionsView()
                .id(transactionsResetToken)
                .tag(RootTab.transactions)
                .tabItem {
                    Label("流水", systemImage: "list.bullet.rectangle")
                }
            ImportReceiptView()
                .id(importsResetToken)
                .tag(RootTab.imports)
                .tabItem {
                    Label("识图", systemImage: "camera.viewfinder")
                }
            MoreHubView()
                .id(moreResetToken)
                .tag(RootTab.more)
                .tabItem {
                    Label("更多", systemImage: "ellipsis.circle")
                }
        }
        .tint(Color.accentColor)
        .appBackdrop()
        .onChange(of: selection) { _, newValue in
            resetCurrentTab(newValue)
        }
    }

    private func resetCurrentTab(_ tab: RootTab) {
        NotificationCenter.default.post(name: .smartLedgerResetTabRoot, object: tab)
        switch tab {
        case .dashboard:
            dashboardResetToken = UUID()
        case .books:
            booksResetToken = UUID()
        case .transactions:
            transactionsResetToken = UUID()
        case .imports:
            importsResetToken = UUID()
        case .more:
            moreResetToken = UUID()
        }
    }
}

extension Notification.Name {
    static let smartLedgerResetTabRoot = Notification.Name("smartledger.resetTabRoot")
}

enum RootTab: Hashable {
    case dashboard
    case books
    case transactions
    case imports
    case more
}

private struct MoreHubView: View {
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                NavigationLink {
                    BudgetsView()
                } label: {
                    Label("预算", systemImage: "creditcard")
                }

                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("分类", systemImage: "square.grid.2x2")
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .scrollContentBackground(.hidden)
            .appBackdrop()
            .navigationTitle("更多")
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartLedgerResetTabRoot)) { note in
            guard let tab = note.object as? RootTab, tab == .more else { return }
            navPath = NavigationPath()
        }
    }
}
