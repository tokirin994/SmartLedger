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
        return store.recommendedBooks(for: draft.happenedAt).filter {
            !selectedIds.contains($0.id) && ($0.autoCollectCategoryIds.isEmpty || $0.autoCollectCategoryIds.contains(draft.categoryId ?? -1))
        }
    }

    private var splitParticipants: [BookParticipant] {
        selectedBook?.participants ?? []
    }

    private var selectedBookSupportsSplit: Bool {
        selectedBook?.splitEnabled == true
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
                    }
                    .buttonStyle(.plain)

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
                                Text(selectedBookNamesText)
                                    .foregroundStyle(selectedBooks.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    if settings.bookAssignmentPromptEnabled, !suggestedBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(editingTransaction == nil ? "符合这些账本时间范围" : "可补充关联到这些账本")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(suggestedBooks) { book in
                                Button {
                                    if !draft.bookIds.contains(book.id) {
                                        draft.bookIds.append(book.id)
                                        draft.bookId = draft.bookIds.first
                                    }
                                } label: {
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
                        }
                    }

                    if let selectedBook, selectedBookSupportsSplit {
                        Section("多人分账 - \(selectedBook.name)") {
                            Picker("付款人", selection: Binding(
                                get: { draft.paidByParticipantId },
                                set: { draft.paidByParticipantId = $0 }
                            )) {
                                Text("请选择付款人").tag(String?.none)
                                ForEach(splitParticipants) { participant in
                                    Text(participant.name).tag(Optional(participant.id))
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
                                            set: { enabled in
                                                let participantId = participant.id
                                                if enabled {
                                                    if !draft.splitParticipantIds.contains(participantId) {
                                                        draft.splitParticipantIds.append(participantId)
                                                    }
                                                } else {
                                                    draft.splitParticipantIds.removeAll(where: { id in
                                                        id == participantId
                                                    })
                                                }
                                            }
                                        )
                                    )
                                }
                            }
                        }
                    }

                    Section("分期") {
                        Toggle("启用分期", isOn: $draft.installmentEnabled)
                        if draft.installmentEnabled {
                            Stepper("分期月数: \(draft.installmentMonths)", value: $draft.installmentMonths, in: 1...36)
                            DatePicker("起始月份", selection: $draft.installmentStartMonth, displayedComponents: .date)
                        }
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
            .disabled(
                draft.title.isEmpty ||
                Double(draft.amount) == nil ||
                (selectedBookSupportsSplit && (draft.paidByParticipantId == nil ||
                draft.splitParticipantIds.isEmpty))
            )
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
}
}

private var selectedBookNamesText: String {
    let names = selectedBooks.map(\.name)
    return names.isEmpty ? "不归属于主题账本" : names.joined(separator: "、")
}

private var selectedCategoryDisplayName: String {
    guard let categoryId = draft.categoryId,
          let category = store.selectableCategories(for: draft.kind).first(where: { $0.id == categoryId })
          ?? store.flattenedCategories.first(where: { $0.id == categoryId }) else {
        return "请选择"
    }
    return category.name
}

private func applyRecommendedBooksBeforeSave() {
    guard !settings.bookAssignmentPromptEnabled else {
        draft.bookId = draft.bookIds.first
        return
    }

    let autoCollectBooks = store.recommendedBooks(for: draft.happenedAt)
        .filter { store.shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId) }

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
    if !draft.paymentMethod.isEmpty {
        draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
    }

    applyRecommendedBooksBeforeSave()

    if let editingTransaction {
        await store.updateTransaction(editingTransaction.id, with: draft)
    } else {
        await store.createTransaction(draft)
    }

    if store.errorMessage == nil {
        dismiss()
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
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
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
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
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

private struct ExpandableCategorySelectionRow: View {
    let category: LedgerCategory
    @Binding var selectedCategoryId: Int?
    let onComplete: () -> Void

    @State private var expanded = false

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
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 6) {
                    ForEach(category.children) { child in
                        ExpandableCategorySelectionRow(category: child, selectedCategoryId: $selectedCategoryId, onComplete: onComplete)
                            .padding(.leading, 12)
                    }
                }
                .padding(.top, 4)
            } label: {
                Button {
                    selectedCategoryId = category.id
                    onComplete()
                } label: {
                    row(category)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
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
                    onCreateCategory: onCreateCategory
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
                    NavigationLink {
                        CategoryNodeSelectionView(
                            category: category,
                            selectedCategoryId: $selectedCategoryId,
                            onComplete: onComplete,
                            flowType: flowType,
                            onCreateCategory: onCreateCategory
                        )
                    } label: {
                        HStack(spacing: 12) {
                            categoryRowTitle(category)
                            Spacer()
                            if selectedCategoryId == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
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
}

private struct CategoryNodeSelectionView: View {
    let category: LedgerCategory
    @Binding var selectedCategoryId: Int?
    let onComplete: () -> Void
    let flowType: FlowType
    let onCreateCategory: ((Int?) -> Void)?

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
                        NavigationLink {
                            CategoryNodeSelectionView(
                                category: child,
                                selectedCategoryId: $selectedCategoryId,
                                onComplete: onComplete,
                                flowType: flowType,
                                onCreateCategory: onCreateCategory
                            )
                        } label: {
                            HStack(spacing: 12) {
                                rowTitle(child)
                                Spacer()
                                if selectedCategoryId == child.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
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
