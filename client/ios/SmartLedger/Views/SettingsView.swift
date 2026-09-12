import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @State private var cloudEnabled = false
    @State private var newChannel = ""
    @State private var demoMessage: String?

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题模式", selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }

            Section("坚果云 WebDAV 同步") {
                TextField("WebDAV 地址", text: $settings.jianguoyunEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("坚果云账号", text: $settings.jianguoyunUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("应用密码", text: $settings.jianguoyunAppPassword)
                Text("请在坚果云账户安全设置中创建应用密码；建议使用独立的 SmartLedger 目录。")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("启用坚果云同步", isOn: $cloudEnabled)
                    .onChange(of: cloudEnabled) { _, enabled in
                        Task { await store.setCloudSyncEnabled(enabled) }
                    }
                LabeledContent("配置状态", value: settings.jianguoyunConfigured ? "已配置" : "待填写")
                LabeledContent("同步状态", value: store.syncState.title)
                if let time = store.lastSyncAt { LabeledContent("最近同步", value: time.formatted(date: .abbreviated, time: .shortened)) }
                Text(store.lastSyncMessage).font(.footnote).foregroundStyle(.secondary)
                if store.syncState == .syncing || store.syncState == .checking { ProgressView("正在同步") }
                Button("检查 WebDAV 配置") { Task { await store.refreshCloudAccountState() } }
                Button("智能同步") { Task { await store.smartSync() } }
                    .disabled(!cloudEnabled || !settings.jianguoyunConfigured || store.syncState == .syncing)
                Button("仅推送到坚果云") { Task { await store.pushToCloud() } }
                    .disabled(!cloudEnabled || !settings.jianguoyunConfigured || store.syncState == .syncing)
                Button("仅从坚果云拉取") { Task { await store.pullFromCloud() } }
                    .disabled(!cloudEnabled || !settings.jianguoyunConfigured || store.syncState == .syncing)
                if let conflict = store.pendingSyncConflict {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("检测到同步冲突").font(.headline)
                        Text("本地：\(conflict.localTransactionCount) 笔流水、\(conflict.localBookCount) 个账本\n云端：\(conflict.remoteTransactionCount) 笔流水、\(conflict.remoteBookCount) 个账本")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack { Button("保留本地") { Task { await store.useLocalForSyncConflict() } }; Button("采用云端") { Task { await store.useRemoteForSyncConflict() } } }
                    }
                }
            }

            Section("支付渠道") {
                if settings.paymentChannels.isEmpty { Text("暂无").foregroundStyle(.secondary) }
                ForEach(settings.paymentChannels, id: \.self) { channel in
                    Label(channel, systemImage: "creditcard")
                        .swipeActions { Button(role: .destructive) { settings.removePaymentChannel(channel) } label: { Label("删除", systemImage: "trash") } }
                }
                HStack { TextField("新增支付渠道", text: $newChannel); Button("添加") { if settings.registerPaymentChannel(newChannel) != nil { newChannel = "" } } }
            }

            Section("账本归属") {
                Toggle("新流水显示账本归属推荐", isOn: $settings.bookAssignmentPromptEnabled)
                Text("关闭后，符合自动归集规则的新流水会直接归入账本，不再额外提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("开发辅助") {
                Button("生成一批模拟数据") {
                    Task {
                        await store.appendExtendedDemoData()
                        demoMessage = store.errorMessage ?? "已生成模拟账本与 10 笔模拟流水"
                    }
                }
                .disabled(store.isLoading || store.syncState == .syncing)
            }
        }
        .navigationTitle("设置")
        .task { cloudEnabled = store.cloudSyncEnabled }
        .alert("模拟数据", isPresented: Binding(get: { demoMessage != nil }, set: { if !$0 { demoMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(demoMessage ?? "") }
    }
}