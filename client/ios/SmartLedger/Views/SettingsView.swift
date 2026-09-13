import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @State private var cloudEnabled = false
    @State private var cloudConfigurationExpanded = false
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
                Toggle("启用坚果云同步", isOn: $cloudEnabled)
                    .onChange(of: cloudEnabled) { _, enabled in
                        Task { await store.setCloudSyncEnabled(enabled) }
                    }
                HStack(spacing: 10) {
                    Image(systemName: store.cloudAccountStatus == .available ? "checkmark.icloud.fill" : "icloud.slash")
                        .foregroundStyle(store.cloudAccountStatus == .available ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.jianguoyunConfigured ? "坚果云已配置" : "尚未配置坚果云")
                            .font(.subheadline.weight(.medium))
                        Text(store.cloudConnectionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if store.syncState == .syncing || store.syncState == .checking { ProgressView() }
                }
                if let time = store.lastSyncAt { LabeledContent("最近同步", value: time.formatted(date: .abbreviated, time: .shortened)) }
                Picker("自动同步", selection: Binding(get: { store.cloudSyncSchedule }, set: { schedule in
                    Task { await store.updateCloudSyncSchedule(schedule) }
                })) {
                    ForEach(CloudSyncSchedule.allCases) { schedule in
                        Text(schedule.title).tag(schedule)
                    }
                }
                Text(store.cloudSyncSchedule.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                DisclosureGroup("配置与诊断", isExpanded: $cloudConfigurationExpanded) {
                    TextField("WebDAV 地址", text: $settings.jianguoyunEndpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("坚果云账号", text: $settings.jianguoyunUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("应用密码", text: $settings.jianguoyunAppPassword)
                    Text("请在坚果云账户安全设置中创建应用密码；应用会在首次推送时创建 SmartLedger 目录。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("检查 WebDAV 连接") { Task { await store.refreshCloudAccountState() } }
                    Menu("同步操作") {
                        Button("智能同步") { Task { await store.smartSync() } }
                        Button("仅推送到坚果云") { Task { await store.pushToCloud() } }
                        Button("仅从坚果云拉取") { Task { await store.pullFromCloud() } }
                    }
                    .disabled(!cloudEnabled || !settings.jianguoyunConfigured || store.syncState == .syncing)
                    Text("同步会记录最近一次双方一致的内容版本。只有本地和云端都在该版本之后发生变更时，才会提示冲突；连续保存不会再被误判为冲突。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
