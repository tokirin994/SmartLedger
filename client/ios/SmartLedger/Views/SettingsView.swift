import AuthenticationServices
import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @State private var cloudSyncToggle = true
    @State private var showAddPaymentChannelSheet = false
    @State private var backgroundPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题模式", selection: $settings.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("背景图片")
                            Spacer()
                            if settings.hasCustomBackgroundImage {
                                Text("已设置")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("默认")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let previewImage = settings.backgroundPreviewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }

                        HStack(spacing: 12) {
                            PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                                Label(settings.hasCustomBackgroundImage ? "更换背景" : "选择背景", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            if settings.hasCustomBackgroundImage {
                                Button("清除") {
                                    settings.clearBackgroundImage()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section("Apple 账号") {
                    if let profile = store.appleProfile {
                        LabeledContent("账号", value: profile.fullName ?? profile.email ?? profile.userIdentifier)
                        if let email = profile.email {
                            LabeledContent("邮箱", value: email)
                        }
                        LabeledContent("绑定时间", value: profile.authorizedAt.formatted(date: .abbreviated, time: .shortened))

                        Button("清除本地 Apple 账号信息", role: .destructive) {
                            store.clearAppleProfile()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            SignInWithAppleButton(.continue) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                Task { await store.handleAppleSignIn(result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 46)
                        }
                    }
                }

                Section("iCloud / CloudKit 云同步") {
                    Toggle("启用云同步", isOn: $cloudSyncToggle)
                        .onChange(of: cloudSyncToggle) { _, enabled in
                            Task { await store.setCloudSyncEnabled(enabled) }
                        }

                    LabeledContent("iCloud 状态", value: store.cloudAccountStatus.title)
                    LabeledContent("同步状态", value: store.syncState.title)
                    if let recordName = store.cloudUserRecordName {
                        LabeledContent("CloudKit 用户", value: recordName)
                    }
                    LabeledContent("最近同步", value: store.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "尚未同步")

                    Text(store.lastSyncMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if store.syncState == .syncing || store.syncState == .checking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(store.syncState == .checking ? "正在检查 iCloud 账号状态…" : "正在进行 iCloud 同步…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("刷新 iCloud 状态") {
                        Task { await store.refreshCloudAccountState() }
                    }
                    .disabled(store.syncState == .syncing)

                    Button("智能同步（本地 / iCloud 对比）") {
                        Task { await store.smartSync() }
                    }
                    .disabled(!cloudSyncToggle || store.syncState == .syncing)

                    Button("仅推送到 iCloud") {
                        Task { await store.pushToCloud() }
                    }
                    .disabled(!cloudSyncToggle || store.syncState == .syncing)

                    Button("仅从 iCloud 拉取") {
                        Task { await store.pullFromCloud() }
                    }
                    .disabled(!cloudSyncToggle || store.syncState == .syncing)

                    if let conflict = store.pendingSyncConflict {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("检测到同步冲突")
                                .font(.subheadline.weight(.semibold))
                            Text("本地: \(conflict.localUpdatedAt.formatted(date: .abbreviated, time: .shortened)), 流水 \(conflict.localTransactionCount) 笔, 账本 \(conflict.localBookCount) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("云端: \(conflict.remoteUpdatedAt.formatted(date: .abbreviated, time: .shortened)), 流水 \(conflict.remoteTransactionCount) 笔, 账本 \(conflict.remoteBookCount) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Button("保留本地") {
                                    Task { await store.useLocalForSyncConflict() }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("采用云端") {
                                    Task { await store.useRemoteForSyncConflict() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
  }

        Section("支付渠道") {
            if settings.paymentChannels.isEmpty {
                Text("暂无")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.paymentChannels, id: \.self) { channel in
                    HStack(spacing: 12) {
                        Label(channel, systemImage: "creditcard.fill")
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("删除", role: .destructive) {
                            settings.removePaymentChannel(channel)
                        }
                    }
                }

                Button {
                    showAddPaymentChannelSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("新增支付渠道")
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }

        Section("账本归属") {
            Toggle("新流水显示账本归属推荐", isOn: $settings.bookAssignmentPromptEnabled)
            Text("关闭后，如果某个账本已开启自动归集，落在其时间范围内的新流水会直接归入该账本，不再额外提醒。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("开发辅助") {
            Button("生成一批模拟数据") {
                Task { await store.appendExtendedDemoData() }
            }
            .disabled(store.isLoading || store.syncState == .syncing)
        }
    }
    .navigationTitle("设置")
        .task {
            cloudSyncToggle = store.cloudSyncEnabled
            await store.refreshCloudAccountState()
        }
        .onChange(of: backgroundPickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadBackgroundImage(from: newValue) }
        }
        .sheet(isPresented: $showAddPaymentChannelSheet) {
            NavigationStack {
                PaymentChannelSuggestionPickerSheet { channel in
                    _ = settings.registerPaymentChannel(channel)
                    showAddPaymentChannelSheet = false
                }
                .environmentObject(settings)
            }
        }
    .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.errorMessage = nil
    })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
}

private func loadBackgroundImage(from item: PhotosPickerItem) async {
    do {
        let data = try await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data) {
                settings.setBackgroundImage(image)
        }
    } catch {
        store.errorMessage = "读取背景图片失败:\(error.localizedDescription)"
        backgroundPickerItem = nil
    }
}

private struct PaymentChannelSuggestionPickerSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let onSelect: (String) -> Void

    var body: some View {
        List {
            Section("常见类型") {
                ForEach(availableSuggestions, id: \.self) { channel in
                    Button {
                        onSelect(channel)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Label(channel, systemImage: "creditcard.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("新增支付渠道")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private var availableSuggestions: [String] {
        settings.suggestedPaymentChannels.filter { suggestion in
            !settings.paymentChannels.contains { existing in
                existing.caseInsensitiveCompare(suggestion) == .orderedSame
            }
        }
    }
}
