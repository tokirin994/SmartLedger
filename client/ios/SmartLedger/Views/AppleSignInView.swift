import SwiftUI

/// 可复用的 Apple 登录入口；设置页可直接复用，也可用于首次启动引导。
struct AppleSignInView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var coordinator: AppleSignInCoordinator?
    var body: some View {
        Button("使用 Apple 登录") {
            let value = AppleSignInCoordinator { result in
                guard case .success(let profile) = result else { return }
                Task { @MainActor in store.appleProfile = profile; store.save() }
            }
            coordinator = value
            value.start()
        }
    }
}
