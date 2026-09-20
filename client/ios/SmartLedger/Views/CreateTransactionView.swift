import SwiftUI
import UIKit

struct CreateTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TransactionDraft()
    private let editingTransaction: LedgerTransaction?
    private let initialDraft: TransactionDraft
    @State private var showCreateCategorySheet = false
    @State private var categoryCreationParentId: Int?
    @State private var showCategoryPicker = false
    @State private var showUnsavedChangesDialog = false
    @State private var saveFailureMessage: String?
    @State private var showOffsetOverLimitConfirmation = false
    @State private var showCancelInstallmentConfirmation = false
    @State private var showPayoffInstallmentConfirmation = false

    init(editingTransaction: LedgerTransaction? = nil) {
        self.editingTransaction = editingTransaction
        let seedDraft = editingTransaction.map(TransactionDraft.init(transaction:)) ?? TransactionDraft()
        self.initialDraft = seedDraft
        _draft = State(initialValue: seedDraft)
    }

    private var selectedBooks: [LedgerBook] {
        let ids = !draft.bookIds.isEmpty ? draft.bookIds : (draft.bookId.map { [$0] } ?? [])
        return store.books.filter { ids.contains($0.id) }
    }

    private var selectedBook: LedgerBook? {
        selectedBooks.first
    }

    private var suggestedBooks: [LedgerBook] {
        let selectedIds = Set(draft.bookIds)
        // “符合账本期间”只是创建时的辅助推荐，不应受自动归集开关或归集类别限制。
        return store.recommendedBooks(for: draft.happenedAt).filter { !selectedIds.contains($0.id) }
    }

    private var splitParticipants: [BookParticipant] {
        selectedBook?.participants ?? []
    }

    private var selectedBookSupportsSplit: Bool {
        selectedBook?.splitEnabled == true
    }

    private var selectedBookUsesAnonymousSplit: Bool {
        selectedBook?.autoCollectEnabled == true && selectedBook?.splitEnabled == true
    }

    private var selectedBookRequiresNamedSplit: Bool {
        selectedBookSupportsSplit && !selectedBookUsesAnonymousSplit
    }

    private var editingInstallment: Bool {
        editingTransaction?.installmentGroupId != nil
    }

    private var existingOffsetTransactions: [LedgerTransaction] {
        guard let sourceId = editingTransaction?.id else { return [] }
        return store.transactions.filter { $0.linkedOffsetSourceID == sourceId && $0.kind == .income }
    }

    private var existingOffsetAmount: Double {
        existingOffsetTransactions.reduce(0) { $0 + $1.amount }
    }

    private var existingOffsetRatio: Double {
        guard let sourceAmount = editingTransaction?.amount, sourceAmount > 0 else { return 0 }
        return existingOffsetAmount / sourceAmount * 100
    }

    private func addSuggestedBook(_ book: LedgerBook) {
        guard !draft.bookIds.contains(book.id) else { return }
        draft.bookIds.append(book.id)
        draft.bookId = draft.bookIds.first
    }

    @ViewBuilder
    private func suggestedBookRow(_ book: LedgerBook) -> some View {
        Button { addSuggestedBook(book) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(.purple)
                Text(book.name)
                    .foregroundStyle(.primary)
                Spacer()
                if draft.bookIds.contains(book.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                } else {
                    Text("添加")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var categoryPickerRow: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack {
                Text("分类")
                    .foregroundStyle(.primary)
                Spacer()
                Text(selectedCategoryDisplayName)
                    .foregroundStyle(draft.categoryId == nil ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    Picker("类型", selection: $draft.kind) {
                        ForEach(FlowType.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("标题", text: $draft.title)
                    TextField("金额", text: $draft.amount)
                        .keyboardType(.decimalPad)
                    PaymentChannelField(selection: $draft.paymentMethod, title: "支付渠道")
                    DatePicker("时间", selection: $draft.happenedAt)
                }

                Section("分类") {
                    categoryPickerRow

                    if store.books.isEmpty {
                        Text("暂无账本")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            TransactionBooksPickerView(selectedBookIds: $draft.bookIds)
                                .environmentObject(store)
                        } label: {
                            HStack {
                                Text("账本归属")
                                Spacer()
                                TransactionBooksSummaryRow(names: selectedBooks.map(\.name))
                            }
                        }
                    }

                    if settings.bookAssignmentPromptEnabled, !suggestedBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(editingTransaction == nil ? "符合这些账本时间范围" : "可补充关联到这些账本")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(suggestedBooks) { book in
                                suggestedBookRow(book)
                            }
                        }
                    }

                    if let selectedBook, selectedBookSupportsSplit {
                        Section("多人分账 - \(selectedBook.name)") {
                            if selectedBookUsesAnonymousSplit {
                                Label("自动归集账本按 \(splitParticipants.count) 人均分，不记录具体付款人", systemImage: "person.3.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("付款人", selection: Binding(
                                get: { draft.paidByParticipantId },
                                set: { draft.paidByParticipantId = $0 }
                                )) {
                                    Text("请选择付款人").tag(String?.none)
                                    ForEach(splitParticipants) { participant in
                                        let participantId = participant.id
                                        Text(participant.name).tag(Optional(participantId))
                                    }
                                }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("参与分账成员")
                                    .font(.subheadline.weight(.medium))

                                ForEach(splitParticipants) { participant in
                                    Toggle(
                                        participant.name,
                                        isOn: Binding(
                                            get: { draft.splitParticipantIds.contains(participant.id) },
                        set: { setParticipant(participant.id, enabled: $0) }
                                        )
                                    )
                                }
                            }
                            }
                        }
                    }

                    Section("分期") {
                        if editingInstallment {
                            Label("这是一组已有的分期流水，编辑不会重新拆分金额。", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("取消分期并合并") { showCancelInstallmentConfirmation = true }
                            Button("立即还清剩余分期") { showPayoffInstallmentConfirmation = true }
                                .foregroundStyle(.orange)
                        } else {
                            Toggle("启用分期", isOn: $draft.installmentEnabled)
                                .disabled(editingTransaction != nil)
                            if editingTransaction != nil {
                                Text("已有流水不能重新开启分期；如需分期请新增一笔流水。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if draft.installmentEnabled && editingTransaction == nil {
                                Stepper("分期月数: \(draft.installmentMonths)", value: $draft.installmentMonths, in: 1...36)
                                DatePicker("起始月份", selection: $draft.installmentStartMonth, displayedComponents: .date)
                            }
                        }
                    }

                    if draft.kind == .expense {
                        OffsetDraftSection(
                            offsets: $draft.offsets,
                            amount: transactionAmount,
                            happenedAt: draft.happenedAt,
                            preferredCategoryID: preferredOffsetCategoryID,
                            categories: offsetIncomeCategories,
                            existingRatio: existingOffsetRatio,
                            existingAmount: existingOffsetAmount
                        )
                    }

                    Section("高级字段") {
                        TextField("商户", text: $draft.merchant)
                        TextField("备注", text: $draft.note, axis: .vertical)
                        TextField("原价", text: $draft.originalAmount)
                            .keyboardType(.decimalPad)
                        TextField("优惠金额", text: $draft.discountAmount)
                            .keyboardType(.decimalPad)
                        TextField("溢价金额", text: $draft.premiumAmount)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .dismissKeyboardWhenTappedOutside()
            .navigationTitle(editingTransaction == nil ? "新增流水" : "修改流水")
            .task {
                if store.books.isEmpty {
                    await store.loadBooks()
               }
        if store.categories.isEmpty {
            await store.loadCategories()
        }
    }
    .onChange(of: draft.kind) { _, newKind in
        if let selectedCategoryId = draft.categoryId,
           !store.selectableCategories(for: newKind).contains(where: { $0.id == selectedCategoryId }) {
            draft.categoryId = nil
        }
    }
    .onChange(of: draft.installmentEnabled) { _, enabled in
        if !enabled {
            draft.installmentMonths = 1
        }
    }
    .onChange(of: draft.bookId) { _, newBookId in
        guard let book = store.books.first(where: { $0.id == newBookId }) else {
            draft.paidByParticipantId = nil
            draft.splitParticipantIds = []
            return
        }

        guard book.splitEnabled else {
            draft.paidByParticipantId = nil
            draft.splitParticipantIds = []
            return
        }

        let participants = book.participants
        if !participants.contains(where: { $0.id == draft.paidByParticipantId }) {
            draft.paidByParticipantId = participants.first(where: { $0.name == "我" })?.id ?? participants.first?.id
        }

        let validIds = Set(participants.map(\.id))
        draft.splitParticipantIds = draft.splitParticipantIds.filter { validIds.contains($0) }
        if draft.splitParticipantIds.isEmpty {
            draft.splitParticipantIds = participants.map(\.id)
        }
    }
    .onChange(of: draft.bookIds) { _, ids in
        let firstId = ids.first
        if draft.bookId != firstId { draft.bookId = firstId }
    }
    .toolbar {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { attemptDismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("保存") {
                Task { await saveDraftAndDismiss() }
            }
        }
    }
    .background(
        SheetDismissGuard(isDisabled: hasUnsavedChanges) {
            showUnsavedChangesDialog = true
        }
    )
    .sheet(isPresented: $showCreateCategorySheet) {
        CategoryEditorSheet(
            title: "新增分类",
            preselectedFlowType: draft.kind,
            preselectedParentId: categoryCreationParentId,
            onCreated: { category in
                draft.categoryId = category.id
                categoryCreationParentId = nil
                showCreateCategorySheet = false
            }
        )
        .environmentObject(store)
    }
    .sheet(isPresented: $showCategoryPicker) {
        NavigationStack {
            CategoryRootPickerSheet(
                categories: store.categories.filter { $0.flowType == draft.kind },
                selectedCategoryId: $draft.categoryId,
                onCreateCategory: { parentId in
                    categoryCreationParentId = parentId
                    showCategoryPicker = false
                    showCreateCategorySheet = true
                }
            )
        }
    }
    .confirmationDialog("改动还未保存", isPresented: $showUnsavedChangesDialog, titleVisibility: .visible) {
        Button("保存") {
            Task { await saveDraftAndDismiss() }
        }
        Button("丢弃更改", role: .destructive) {
            dismiss()
        }
        Button("继续编辑", role: .cancel) {}
    } message: {
        Text("退出前可以选择先保存，或者直接丢弃这次改动。")
    }
    .alert("无法保存流水", isPresented: saveFailureBinding) {
        Button("知道了", role: .cancel) {}
    } message: {
        Text(saveFailureMessage ?? "请检查填写内容后重试。")
    }
    .sheet(isPresented: $showOffsetOverLimitConfirmation) {
        OffsetLimitConfirmationSheet(
            ratio: combinedOffsetRatio,
            amount: combinedOffsetAmount,
            onKeep: { showOffsetOverLimitConfirmation = false; Task { await performSaveDraft(normalizeOffsets: false) } },
            onNormalize: { showOffsetOverLimitConfirmation = false; Task { await performSaveDraft(normalizeOffsets: true) } }
        )
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
    .confirmationDialog("取消分期并合并？", isPresented: $showCancelInstallmentConfirmation, titleVisibility: .visible) {
        Button("合并为一笔流水", role: .destructive) {
            Task { await cancelInstallment() }
        }
        Button("继续编辑", role: .cancel) {}
    } message: {
        Text("所有已生成的分期金额会合并为一笔，未来分期不再单独显示。")
    }
    .confirmationDialog("立即还清剩余分期？", isPresented: $showPayoffInstallmentConfirmation, titleVisibility: .visible) {
        Button("立即还清", role: .destructive) {
            requestPayOffInstallment()
        }
        Button("取消", role: .cancel) {}
    } message: {
        Text("会生成一笔当前时间的还清流水，并移除尚未到期的分期记录。")
    }
}
}
private var saveFailureBinding: Binding<Bool> {
    Binding(
        get: { saveFailureMessage != nil },
        set: { if !$0 { saveFailureMessage = nil } }
    )
}

private var selectedBookNamesText: String {
    let names = selectedBooks.map(\.name)
    return names.isEmpty ? "不归属于主题账本" : names.joined(separator: "、")
}

private var preferredOffsetCategoryID: Int? {
    let income = store.flattenedCategories.filter { $0.flowType == .income }
    return income.first(where: { $0.displayName.contains("报销") })?.id
        ?? income.first(where: { $0.displayName.contains("退款") })?.id
        ?? income.first?.id
}

private var transactionAmount: Double {
    Double(draft.amount) ?? 0
}

private func offsetGeneratedAmount(for offset: OffsetDraft) -> Double {
    ((Double(draft.amount) ?? 0) * max(offset.ratio, 0) / 100 * 100).rounded() / 100
}

private var totalOffsetRatio: Double { draft.offsets.reduce(0) { $0 + max($1.ratio, 0) } }
private var totalOffsetAmount: Double { draft.offsets.reduce(0) { $0 + offsetGeneratedAmount(for: $1) } }
private var combinedOffsetRatio: Double { existingOffsetRatio + totalOffsetRatio }
private var combinedOffsetAmount: Double { existingOffsetAmount + totalOffsetAmount }
private var offsetIncomeCategories: [LedgerCategory] {
    store.flattenedCategories.filter { $0.flowType == .income }
}

private func requestPayOffInstallment() {
    Task { await payOffInstallment() }
}

private var selectedCategoryDisplayName: String {
    guard let categoryId = draft.categoryId,
          let category = store.selectableCategories(for: draft.kind).first(where: { $0.id == categoryId })
          ?? store.flattenedCategories.first(where: { $0.id == categoryId }) else {
        return "请选择"
    }
    return category.name
}

private func setParticipant(_ id: String, enabled: Bool) {
    if enabled {
        if !draft.splitParticipantIds.contains(id) {
            draft.splitParticipantIds.append(id)
        }
    } else {
        draft.splitParticipantIds.removeAll { $0 == id }
    }
}

private func applyRecommendedBooksBeforeSave() {
    guard !settings.bookAssignmentPromptEnabled else {
        draft.bookId = draft.bookIds.first
        return
    }

    let autoCollectBooks = store.recommendedBooks(for: draft.happenedAt)
        .filter { store.shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId, kind: draft.kind) }

    for book in autoCollectBooks where !draft.bookIds.contains(book.id) {
        draft.bookIds.append(book.id)
    }

    draft.bookId = draft.bookIds.first
}

private var hasUnsavedChanges: Bool {
    TransactionEditorStateSnapshot(draft: draft) != TransactionEditorStateSnapshot(draft: initialDraft)
}

private func attemptDismiss() {
    if hasUnsavedChanges {
        showUnsavedChangesDialog = true
    } else {
        dismiss()
    }
}

private func saveDraftAndDismiss() async {
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
        saveFailureMessage = "请填写流水标题，例如“午餐”或“工资到账”。"
        return
    }
    guard let amount = Double(draft.amount), amount > 0 else {
        saveFailureMessage = "金额必须是大于 0 的数字。"
        return
    }
    if draft.offsets.contains(where: { $0.categoryId == nil }) {
        saveFailureMessage = "请为抵扣流水选择“报销”或“退款”收入分类。"
        return
    }
    if combinedOffsetRatio > 100 {
        showOffsetOverLimitConfirmation = true
        return
    }
    await performSaveDraft(normalizeOffsets: false)
}

private func performSaveDraft(normalizeOffsets: Bool) async {
    if normalizeOffsets, totalOffsetRatio > 0 {
        let availableRatio = max(100 - existingOffsetRatio, 0)
        let scale = availableRatio / totalOffsetRatio
        for index in draft.offsets.indices { draft.offsets[index].ratio *= scale }
    }
    if selectedBookRequiresNamedSplit && draft.paidByParticipantId == nil {
        saveFailureMessage = "该账本启用了分账，请选择付款人。"
        return
    }
    if selectedBookRequiresNamedSplit && draft.splitParticipantIds.isEmpty {
        saveFailureMessage = "该账本启用了分账，请至少选择一位分账成员。"
        return
    }

    store.errorMessage = nil
    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !draft.paymentMethod.isEmpty {
        draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
    }

    applyRecommendedBooksBeforeSave()

    if let editingTransaction {
        await store.updateTransaction(editingTransaction.id, with: draft)
        if store.errorMessage == nil && !draft.offsets.isEmpty {
            await store.createOffsets(for: editingTransaction.id, offsets: draft.offsets)
        }
    } else {
        await store.createTransaction(draft)
    }

    if let error = store.errorMessage {
        saveFailureMessage = error
    } else {
        dismiss()
    }
}

private func cancelInstallment() async {
    guard let editingTransaction else { return }
    store.errorMessage = nil
    await store.cancelInstallment(for: editingTransaction.id)
    if let error = store.errorMessage {
        saveFailureMessage = error
    } else {
        dismiss()
    }
}

private func payOffInstallment() async {
    guard let editingTransaction else { return }
    store.errorMessage = nil
    await store.payOffInstallment(for: editingTransaction.id)
    if let error = store.errorMessage {
        saveFailureMessage = error
    } else {
        dismiss()
    }
}
}

private struct TransactionBooksSummaryRow: View {
    let names: [String]
    var body: some View {
        Text(names.isEmpty ? "不归属于主题账本" : names.joined(separator: "、"))
            .foregroundStyle(names.isEmpty ? .secondary : .primary)
            .multilineTextAlignment(.trailing)
    }
}

private struct OffsetIncomeCategoryPicker: View {
    @Binding var categoryId: Int?
    let categories: [LedgerCategory]

    var body: some View {
        Picker("收入分类", selection: $categoryId) {
            Text("请选择收入分类").tag(Int?.none)
            ForEach(categories, id: \.id) { category in
                OffsetIncomeCategoryPickerItem(category: category)
            }
        }
    }
}

private struct OffsetIncomeCategoryPickerItem: View {
    let category: LedgerCategory

    var body: some View {
        let categoryId: Int? = category.id
        Text(category.displayName).tag(categoryId)
    }
}

private struct OffsetLimitConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let ratio: Double
    let amount: Double
    let onKeep: () -> Void
    let onNormalize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("累计抵扣超过 100%", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("取消") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            Text("当前累计 \(Int(ratio.rounded()))%，预计生成 \(amount.cnyText) 的收入。请选择如何处理新增抵扣。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button("仍按原比例创建") { onKeep() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("调整新增抵扣至合计 100%") { onNormalize() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .presentationBackground(.regularMaterial)
    }
}

private struct OffsetDraftSection: View {
    @Binding var offsets: [OffsetDraft]
    let amount: Double
    let happenedAt: Date
    let preferredCategoryID: Int?
    let categories: [LedgerCategory]
    let existingRatio: Double
    let existingAmount: Double

    private var totalRatio: Double {
        offsets.reduce(0) { $0 + $1.ratio }
    }

    private var totalAmount: Double {
        existingAmount + offsets.reduce(0) { $0 + amount * $1.ratio / 100 }
    }

    var body: some View {
        Section("抵扣 / 报销") {
            ForEach($offsets) { $offset in
                OffsetIncomeCategoryPicker(categoryId: $offset.categoryId, categories: categories)
                DatePicker("抵扣时间", selection: $offset.happenedAt)
                HStack {
                    Text("抵扣比例")
                    Slider(value: $offset.ratio, in: 0...200, step: 1)
                    let percentage = Int(offset.ratio.rounded())
                    Text("\(percentage)%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                LabeledContent("本笔预计收入", value: (amount * offset.ratio / 100).cnyText)
                    .font(.subheadline.weight(.semibold))
                Button("移除本笔抵扣", role: .destructive) {
                    offsets.removeAll { $0.id == offset.id }
                }
            }
            if !offsets.isEmpty {
                LabeledContent("累计抵扣", value: "\(Int(existingRatio + totalRatio))% · \(totalAmount.cnyText)")
                    .font(.subheadline.weight(.semibold))
            } else if existingRatio > 0 {
                LabeledContent("已抵扣", value: "\(Int(existingRatio))% · \(existingAmount.cnyText)")
                    .font(.subheadline.weight(.semibold))
            }
            Button {
                let available = max(100 - existingRatio - totalRatio, 0)
                offsets.append(OffsetDraft(categoryId: preferredCategoryID, ratio: available > 0 ? available : 100, happenedAt: happenedAt))
            } label: {
                Label("添加抵扣 / 报销", systemImage: "plus.circle.fill")
            }
        }
    }
}

private struct TransactionEditorStateSnapshot: Equatable {
    let title: String
    let amount: String
    let kind: FlowType
    let happenedAt: Date
    let categoryId: Int?
    let bookIds: [Int]
    let note: String
    let merchant: String
    let paymentMethod: String
    let originalAmount: String
    let discountAmount: String
    let premiumAmount: String
    let installmentEnabled: Bool
    let installmentMonths: Int
    let installmentStartMonth: Date
    let paidByParticipantId: String?
    let splitParticipantIds: [String]
    let offsets: [OffsetDraft]

    init(draft: TransactionDraft) {
        self.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = draft.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = draft.kind
        self.happenedAt = draft.happenedAt
        self.categoryId = draft.categoryId
        self.bookIds = draft.bookIds.sorted()
        self.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        self.paymentMethod = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originalAmount = draft.originalAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.discountAmount = draft.discountAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.premiumAmount = draft.premiumAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        self.installmentEnabled = draft.installmentEnabled
        self.installmentMonths = draft.installmentMonths
        self.installmentStartMonth = draft.installmentStartMonth
        self.paidByParticipantId = draft.paidByParticipantId
        self.splitParticipantIds = draft.splitParticipantIds.sorted()
        self.offsets = draft.offsets
    }
}

private struct CategoryRootPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [LedgerCategory]
    @Binding var selectedCategoryId: Int?
    let onCreateCategory: ((Int?) -> Void)?

    var body: some View {
        List {
            Section {
                Button {
                    selectedCategoryId = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("未分类")
                        Spacer()
                        if selectedCategoryId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section("一级分类") {
                ForEach(categories) { category in
                    if category.children.isEmpty {
                        Button {
                            selectedCategoryId = category.id
                            dismiss()
                        } label: {
                            categoryRow(category)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ExpandableCategorySelectionSheet(
                                rootCategory: category,
                                selectedCategoryId: $selectedCategoryId,
                                onCreateCategory: onCreateCategory,
                                onComplete: { dismiss() }
                            )
                        } label: {
                            categoryRow(category)
                        }
                    }
                }
            }

            if let onCreateCategory {
                Section {
                    Button {
                        onCreateCategory(nil)
                    } label: {
                        Label("新建一级分类", systemImage: "folder.badge.plus")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("选择分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ item: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: item.color ?? "#5B8DEF"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: item.color ?? "#5B8DEF").opacity(0.14), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(.primary)
                if !item.children.isEmpty { Text("包含 \(item.children.count) 个子分类").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if selectedCategoryId == item.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct ExpandableCategorySelectionSheet: View {
    let rootCategory: LedgerCategory
    @Binding var selectedCategoryId: Int?
    let onCreateCategory: ((Int?) -> Void)?
    let onComplete: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    selectedCategoryId = rootCategory.id
                    onComplete()
                } label: {
                    row(rootCategory)
                }
                .buttonStyle(.plain)
            } header: {
                Text("当前大类")
            }

            Section("下级分类") {
                ForEach(rootCategory.children) { child in
                    ExpandableCategorySelectionRow(category: child, selectedCategoryId: $selectedCategoryId, onComplete: onComplete)
                }
            }

            if let onCreateCategory {
                Section {
                    Button {
                        onCreateCategory(rootCategory.id)
                    } label: {
                        Label("在这一层新增分类", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(rootCategory.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ item: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: item.color ?? "#5B8DEF"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: item.color ?? "#5B8DEF").opacity(0.14), in: Circle())
            }
            Text(item.name).foregroundStyle(.primary)
            Spacer()
            if selectedCategoryId == item.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct ExpandableCategorySelectionRow: View {
    let category: LedgerCategory
    @Binding var selectedCategoryId: Int?
    let onComplete: () -> Void

    var body: some View {
        if category.children.isEmpty {
            Button {
                selectedCategoryId = category.id
                onComplete()
            } label: {
                row(category)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ExpandableCategorySelectionSheet(
                    rootCategory: category,
                    selectedCategoryId: $selectedCategoryId,
                    onCreateCategory: nil,
                    onComplete: onComplete
                )
            } label: {
                row(category, showsHierarchy: true)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: LedgerCategory, showsHierarchy: Bool = false) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: item.color ?? "#5B8DEF"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: item.color ?? "#5B8DEF").opacity(0.14), in: Circle())
            }
            Text(item.name)
                .foregroundStyle(.primary)
            Spacer()
            if selectedCategoryId == item.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct TransactionBooksPickerView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBookIds: [Int]

    var body: some View {
        List {
            ForEach(store.books) { book in
                Button {
                    if let index = selectedBookIds.firstIndex(of: book.id) {
                        selectedBookIds.remove(at: index)
                    } else {
                        selectedBookIds.append(book.id)
                    }
                } label: {
                    HStack {
                        Text(book.name)
                        Spacer()
                        if selectedBookIds.contains(book.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("账本归属")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }
}

struct PaymentChannelField: View {
    @Binding var selection: String
    var title: String = "支付渠道"
    var placeholder: String = "请选择"

    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack(spacing: 12) {
                if !title.isEmpty {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(selectionDisplay)
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresenting) {
            NavigationStack {
                PaymentChannelPickerSheet(selection: $selection)
            }
        }
    }

    private var selectionDisplay: String {
        selection.isEmpty ? placeholder : selection
    }
}

private struct PaymentChannelPickerSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""

    var body: some View {
        List {
            if !selection.isEmpty {
                Section {
                    Button("清空") {
                        selection = ""
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("常用渠道") {
                ForEach(filteredChannels, id: \.self) { channel in
                Button {
                    selection = settings.registerPaymentChannel(channel) ?? channel
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Label(channel, systemImage: "creditcard.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        if isSelected(channel) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        if let newChannel = addableChannel {
            Section {
                Button {
                    selection = settings.registerPaymentChannel(newChannel) ?? newChannel
                    dismiss()
                } label: {
                    Label("新增\"\(newChannel)\"", systemImage: "plus.circle.fill")
                }
            }
        }
    }
    .navigationTitle("支付渠道")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: "搜索或新增")
    .toolbar {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
    }
}

private var filteredChannels: [String] {
    let channels = settings.paymentChannels
    guard let normalized = normalizedQuery else { return channels }
    return channels.filter { $0.localizedCaseInsensitiveContains(normalized) }
}

private var addableChannel: String? {
    guard let normalized = normalizedQuery else { return nil }
    guard !settings.paymentChannels.contains(where: { isSameChannel($0, normalized) }) else { return nil }
    return normalized
    }
    
    private var normalizedQuery: String? {
        let trimmed = query
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func isSelected(_ channel: String) -> Bool {
        isSameChannel(channel, selection)
    }
    
    private func isSameChannel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

struct HierarchicalCategoryPicker: View {
    let title: String
    let categories: [LedgerCategory]
    let placeholder: String
    let helperText: String?
    @Binding var selectedCategoryId: Int?
    let flowType: FlowType
    let onCreateCategory: ((Int?) -> Void)?
    /// 叶子节点会直接完成选择；有子节点时才进入下一级。
    var allowsDescendantSelection: Bool = true
    
    @State private var isPresenting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPresenting = true
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectedDisplayName)
                        .foregroundStyle(selectedCategoryId == nil ? .secondary : .primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isPresenting) {
            NavigationStack {
                CategoryLevelPickerView(
                    navigationTitle: title,
                    categories: categories,
                    selectedCategoryId: $selectedCategoryId,
                    onComplete: { isPresenting = false },
                    isRoot: true,
                    flowType: flowType,
                    onCreateCategory: onCreateCategory,
                    allowsDescendantSelection: allowsDescendantSelection
                )
            }
        }
    }
    
    private var selectedDisplayName: String {
        guard let selectedCategoryId else {
            return placeholder
        }
        return displayName(for: selectedCategoryId, in: categories) ?? placeholder
    }
    
    private func displayName(for id: Int, in categories: [LedgerCategory], path: [String] = []) -> String? {
        for category in categories {
            let currentPath = path + [category.name]
            if category.id == id {
                return currentPath.joined(separator: " / ")
            }
            if let child = displayName(for: id, in: category.children, path: currentPath) {
                return child
            }
        }
        return nil
    }
}

private struct CategoryLevelPickerView: View {
    let navigationTitle: String
    let categories: [LedgerCategory]
    @Binding var selectedCategoryId: Int?
    let onComplete: () -> Void
    let isRoot: Bool
    let flowType: FlowType
    let onCreateCategory: ((Int?) -> Void)?
    let allowsDescendantSelection: Bool

    var body: some View {
        List {
            if isRoot {
                Section {
                    Button {
                        selectedCategoryId = nil
                        onComplete()
                    } label: {
                        HStack {
                            Text("未分类")
                            Spacer()
                            if selectedCategoryId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section(isRoot ? "一级分类" : "下一级分类") {
                ForEach(categories) { category in
                    categoryRow(category)
                }

                if let onCreateCategory {
                    Button {
                        onCreateCategory(nil)
                        onComplete()
                    } label: {
                        Label("在当前层级新增分类", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onComplete()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRowTitle(_ category: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = category.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            }
            Text(category.name)
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: LedgerCategory) -> some View {
        // 叶子分类本身就是最终选择，不再额外打开一个“当前分类”页面。
        if category.children.isEmpty || !allowsDescendantSelection {
            Button {
                selectedCategoryId = category.id
                onComplete()
            } label: {
                selectionLabel(for: category)
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink {
                CategoryNodeSelectionView(
                    category: category,
                    selectedCategoryId: $selectedCategoryId,
                    onComplete: onComplete,
                    flowType: flowType,
                    onCreateCategory: onCreateCategory,
                    allowsDescendantSelection: allowsDescendantSelection
                )
            } label: {
                selectionLabel(for: category)
            }
        }
    }

    private func selectionLabel(for category: LedgerCategory) -> some View {
        HStack(spacing: 12) {
            categoryRowTitle(category)
            Spacer()
            if selectedCategoryId == category.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct CategoryNodeSelectionView: View {
    let category: LedgerCategory
    @Binding var selectedCategoryId: Int?
    let onComplete: () -> Void
    let flowType: FlowType
    let onCreateCategory: ((Int?) -> Void)?
    let allowsDescendantSelection: Bool

    var body: some View {
        List {
            Section {
                Button {
                    selectedCategoryId = category.id
                    onComplete()
                } label: {
                    HStack(spacing: 12) {
                        rowTitle(category)
                        Spacer()
                        if selectedCategoryId == category.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
            } header: {
                Text(category.children.isEmpty ? "当前分类" : "将直接记到该大类")
            }

            if !category.children.isEmpty {
                Section("下一级") {
                    ForEach(category.children) { child in
                        childRow(child)
                    }
                }
            }

            if let onCreateCategory {
                Section {
                    Button {
                        onCreateCategory(category.id)
                        onComplete()
                    } label: {
                        Label("在这一层新增分类", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rowTitle(_ category: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = category.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            }
            Text(category.name)
        }
    }

    @ViewBuilder
    private func childRow(_ child: LedgerCategory) -> some View {
        // “外卖”等叶子分类点按后直接回填，不产生空的额外层级页面。
        if child.children.isEmpty || !allowsDescendantSelection {
            Button {
                selectedCategoryId = child.id
                onComplete()
            } label: {
                childSelectionLabel(child)
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink {
                CategoryNodeSelectionView(
                    category: child,
                    selectedCategoryId: $selectedCategoryId,
                    onComplete: onComplete,
                    flowType: flowType,
                    onCreateCategory: onCreateCategory,
                    allowsDescendantSelection: allowsDescendantSelection
                )
            } label: {
                childSelectionLabel(child)
            }
        }
    }

    private func childSelectionLabel(_ child: LedgerCategory) -> some View {
        HStack(spacing: 12) {
            rowTitle(child)
            Spacer()
            if selectedCategoryId == child.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}


typealias CategoryEditorSheet = CategoryEditorView

/// 阻止滑动手势直接关闭 sheet：有未保存更改时拦截下滑手势，触发 onAttempt 回调。
struct SheetDismissGuard: View {
    let isDisabled: Bool
    let onAttempt: () -> Void

    var body: some View {
        EmptyView()
            .interactiveDismissDisabled(isDisabled)
            .background(DismissAttemptObserver(onAttempt: onAttempt))
    }
}

private struct DismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(onAttempt: onAttempt)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onAttempt = onAttempt
    }

    @MainActor
    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void

        init(onAttempt: @escaping () -> Void) {
            self.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachToPresentationController()
        }

        private func attachToPresentationController() {
            var target: UIViewController? = parent
            while let current = target {
                if let presentation = current.presentationController {
                    presentation.delegate = self
                    return
                }
                target = current.parent
            }
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
        }
    }
}
