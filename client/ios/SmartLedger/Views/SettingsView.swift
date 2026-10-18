import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @State private var cloudEnabled = false
    @State private var cloudConfigurationExpanded = false
    @State private var newChannel = ""
    @State private var demoMessage: String?

    /// Demo data is only useful on an empty installation. Once the user has
    /// created meaningful data, keep developer-only entry points out of the
    /// normal settings flow so they cannot be triggered accidentally.
    private var shouldShowDeveloperTools: Bool {
        !store.isLoading && store.transactions.isEmpty && store.budgets.isEmpty && store.books.count <= 1
    }

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
                HStack(spacing: 12) {
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
                Toggle("每天 00:00 兜底同步", isOn: Binding(
                    get: { store.midnightSyncEnabled },
                    set: { enabled in Task { await store.setMidnightSyncEnabled(enabled) } }
                ))
                Text("与上面的同步策略并行。App 在前台运行时按本地时间尝试；若 iOS 当时挂起 App，会在下次打开时补检查。")
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
                    HStack(spacing: 10) {
                        Button {
                            Task { await store.refreshCloudAccountState() }
                        } label: {
                            Label("检查连接", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.syncState == .checking || store.syncState == .syncing)

                        Menu {
                            Button { Task { await store.smartSync() } } label: { Label("智能同步", systemImage: "arrow.triangle.2.circlepath") }
                            Button { Task { await store.pushToCloud() } } label: { Label("仅推送到坚果云", systemImage: "icloud.and.arrow.up") }
                            Button { Task { await store.pullFromCloud() } } label: { Label("仅从坚果云拉取", systemImage: "icloud.and.arrow.down") }
                        } label: {
                            Label("立即同步", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(!cloudEnabled || !settings.jianguoyunConfigured || store.syncState == .syncing)
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
                if settings.paymentChannels.isEmpty {
                    ContentUnavailableView("暂无支付渠道", systemImage: "creditcard", description: Text("添加常用渠道后，可在流水编辑时快速选择。"))
                        .listRowBackground(Color.clear)
                } else {
                    Text("常用渠道 · \(settings.paymentChannels.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                    ForEach(settings.paymentChannels, id: \.self) { channel in
                        HStack(spacing: 12) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            Text(channel)
                                .font(.body.weight(.medium))
                            Spacer(minLength: 8)
                            Button(role: .destructive) {
                                settings.removePaymentChannel(channel)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除\(channel)")
                        }
                        .padding(.vertical, 3)
                        .listRowSeparator(.hidden)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    TextField("添加支付渠道", text: $newChannel)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(addPaymentChannel)
                    Button("添加", action: addPaymentChannel)
                        .fontWeight(.semibold)
                        .disabled(newChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 4)
            }

            Section("账本归属") {
                Toggle(isOn: $settings.bookAssignmentPromptEnabled) {
                    Label("新流水显示账本归属推荐", systemImage: "books.vertical")
                }
                Text("关闭后，符合自动归集规则的新流水会直接归入账本，不再额外提醒。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if shouldShowDeveloperTools {
                Section {
                    Button("生成一批模拟数据") {
                        Task {
                            await store.appendExtendedDemoData()
                            demoMessage = store.errorMessage ?? "已生成模拟账本与 10 笔模拟流水"
                        }
                    }
                    .disabled(store.isLoading || store.syncState == .syncing)
                    Text("仅在尚无流水的空白安装中显示。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("开发辅助", systemImage: "wand.and.stars")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardWhenTappedOutside()
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("设置")
        .task { cloudEnabled = store.cloudSyncEnabled }
        .alert("模拟数据", isPresented: Binding(get: { demoMessage != nil }, set: { if !$0 { demoMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(demoMessage ?? "") }
    }

    private func addPaymentChannel() {
        guard settings.registerPaymentChannel(newChannel) != nil else { return }
        newChannel = ""
    }
}
