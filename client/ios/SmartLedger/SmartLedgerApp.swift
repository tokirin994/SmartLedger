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
    @EnvironmentObject private var store: LedgerStore
    @State private var selection: RootTab = .dashboard
    @State private var dashboardResetToken = UUID()
    @State private var booksResetToken = UUID()
    @State private var transactionsResetToken = UUID()
    @State private var importsResetToken = UUID()
    @State private var moreResetToken = UUID()
    @State private var pendingTabAfterOCRDiscard: RootTab?
    @State private var showOCRDiscardConfirmation = false
    @State private var isRevertingOCRSelection = false

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
        .onChange(of: selection) { oldValue, newValue in
            if isRevertingOCRSelection {
                isRevertingOCRSelection = false
                return
            }
            guard oldValue == .imports,
                  newValue != .imports,
                  store.hasPendingOCRImport else {
                resetCurrentTab(newValue)
                return
            }
            pendingTabAfterOCRDiscard = newValue
            isRevertingOCRSelection = true
            selection = .imports
            showOCRDiscardConfirmation = true
        }
        .alert("丢弃当前识别？", isPresented: $showOCRDiscardConfirmation) {
            Button("继续切换并丢弃", role: .destructive) {
                store.clearOCRImport()
                NotificationCenter.default.post(name: .smartLedgerDiscardOCRImport, object: nil)
                if let destination = pendingTabAfterOCRDiscard {
                    pendingTabAfterOCRDiscard = nil
                    selection = destination
                }
            }
            Button("留在识图页", role: .cancel) { pendingTabAfterOCRDiscard = nil }
        } message: {
            Text("当前图片和待确认流水尚未保存。继续切换会丢弃这些识别内容。")
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
    static let smartLedgerDiscardOCRImport = Notification.Name("smartledger.discardOCRImport")
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
                    BudgetView()
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
