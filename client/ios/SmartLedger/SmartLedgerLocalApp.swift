import SwiftUI

@main
struct SmartLedgerLocalApp: App {
    @StateObject private var store = LedgerStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.preferredColorScheme)
        }
    }
}
