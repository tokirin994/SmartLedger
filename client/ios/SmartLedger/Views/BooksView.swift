import SwiftUI

struct BooksView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showingCreate = false
    @State private var searchText = ""
    @State private var bookToDelete: LedgerBook?

    private var filteredBooks: [LedgerBook] {
        store.books.filter { book in
            searchText.isEmpty || book.name.localizedCaseInsensitiveContains(searchText) || (book.note ?? "").localizedCaseInsensitiveContains(searchText)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            if $0.startDate != $1.startDate { return ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            return $0.id > $1.id
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        bookMetric("账本数", "\(store.books.count)", .blue)
                        bookMetric("主题支出", store.books.reduce(0) { $0 + $1.expenseAmount }.cnyText, .orange)
                        bookMetric("主题收入", store.books.reduce(0) { $0 + $1.incomeAmount }.cnyText, .green)
                    }.listRowBackground(Color.clear)
                }
                Section {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索账本标题", text: $searchText); if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") } } }
                }
                if filteredBooks.isEmpty {
                    Section { ContentUnavailableView(searchText.isEmpty ? "暂无主题账本" : "没有匹配的账本", systemImage: "books.vertical") }
                } else {
                    Section {
                        ForEach(filteredBooks) { book in
                            NavigationLink { BookDetailView(book: book) } label: { BookRow(book: book) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { Task { await store.setBookPinned(book.id, pinned: !book.isPinned) } } label: { Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash" : "pin") }.tint(.orange)
                                    Button(role: .destructive) { bookToDelete = book } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("账本")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await store.loadBooks() } } label: { Image(systemName: "arrow.clockwise") } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingCreate = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingCreate) { BookEditorView(book: nil).environmentObject(store) }
            .alert("删除账本？", isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { if let bookToDelete { Task { await store.deleteBook(bookToDelete.id) }; self.bookToDelete = nil } }
            } message: { Text("删除账本不会删除流水，只会移除流水与该账本的关联。") }
            .task { await store.loadBooks() }
        }
    }

    private func bookMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).glassCard(cornerRadius: 14, strokeOpacity: 0.16)
    }
}
private struct BookRow: View {
    let book: LedgerBook
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: book.icon ?? "book.closed.fill")
                .font(.title3).foregroundStyle(Color(hex: book.color ?? "#4F46E5"))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(book.name).font(.headline); if book.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) } }
                Text(book.note ?? "未填写说明").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("流水 \(book.transactionCount) 笔 · 余额 \(book.balance.cnyText)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.vertical, 5)
    }
}

private struct BookDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook
    @State private var showingEditor = false
    @State private var deleteRequested = false

    private var relatedTransactions: [LedgerTransaction] { store.transactions.filter { $0.bookIds.contains(book.id) || $0.bookId == book.id }.sorted { $0.happenedAt > $1.happenedAt } }
    private var current: LedgerBook { store.books.first(where: { $0.id == book.id }) ?? book }
    private func transactionAmountText(_ transaction: LedgerTransaction) -> String { (transaction.kind == .expense ? -transaction.amount : transaction.amount).cnyText }
    private func transactionAmountColor(_ transaction: LedgerTransaction) -> Color { transaction.kind == .expense ? .primary : .green }
    var body: some View {
        NavigationStack {
            List {
                Section("概览") {
                    LabeledContent("流水数量", value: "\(current.transactionCount) 笔")
                    LabeledContent("收入", value: current.incomeAmount.cnyText)
                    LabeledContent("支出", value: current.expenseAmount.cnyText)
                    LabeledContent("结余", value: current.balance.cnyText)
                }
                Section("高级规则") {
                    LabeledContent("自动归集", value: current.autoCollectEnabled ? "已启用" : "未启用")
                    LabeledContent("归集分类", value: current.autoCollectCategoryIds.isEmpty ? "全部分类" : "\(current.autoCollectCategoryIds.count) 个分类")
                    LabeledContent("预算", value: current.budgetEnabled ? (current.budgetLimitAmount ?? 0).cnyText : "未设置")
                    LabeledContent("成员", value: current.participantNames.isEmpty ? "仅自己" : current.participantNames.joined(separator: "、"))
                }
                if let start = current.startDate { Section("账本期间") { LabeledContent("开始", value: start.formatted(date: .abbreviated, time: .omitted)); if let end = current.endDate { LabeledContent("结束", value: end.formatted(date: .abbreviated, time: .omitted)) } } }
                Section("归集流水") {
                    if relatedTransactions.isEmpty { Text("暂无归集流水").foregroundStyle(.secondary) }
                    ForEach(relatedTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tx.title)
                                Text(tx.happenedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(transactionAmountText(tx)).foregroundStyle(transactionAmountColor(tx))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await store.removeTransaction(tx.id, from: current.id) } } label: { Label("剔除", systemImage: "minus.circle") }
                        }
                    }
                }
            }
            .navigationTitle(current.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Menu { Button("设置") { showingEditor = true }; Button(current.isPinned ? "取消置顶" : "置顶") { Task { await store.setBookPinned(current.id, pinned: !current.isPinned) } }; Button("删除账本", role: .destructive) { deleteRequested = true } } label: { Image(systemName: "ellipsis.circle") } }
            }
            .sheet(isPresented: $showingEditor) { BookEditorView(book: current).environmentObject(store) }
            .alert("删除账本？", isPresented: $deleteRequested) { Button("取消", role: .cancel) {}; Button("删除", role: .destructive) { Task { await store.deleteBook(current.id) }; dismiss() } } message: { Text("删除账本不会删除流水，只会移除关联。") }
        }
    }
}

private struct BookEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook?
    @State private var name: String
    @State private var note: String
    @State private var icon: String
    @State private var color: String
    @State private var isPinned: Bool
    @State private var autoCollectEnabled: Bool
    @State private var selectedCategoryIDs: Set<Int>
    @State private var budgetEnabled: Bool
    @State private var budgetText: String
    @State private var hasDateRange: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var members: [String]
    @State private var newMember = ""
    @State private var showAutoCollectSetup = false
    @State private var collectExistingNow = false
    @State private var iconPickerExpanded = false

    init(book: LedgerBook?) {
        self.book = book
        _name = State(initialValue: book?.name ?? "")
        _note = State(initialValue: book?.note ?? "")
        _icon = State(initialValue: book?.icon ?? "book.closed.fill")
        _color = State(initialValue: book?.color ?? "#4F46E5")
        _isPinned = State(initialValue: book?.isPinned ?? false)
        _autoCollectEnabled = State(initialValue: book?.autoCollectEnabled ?? false)
        _selectedCategoryIDs = State(initialValue: Set(book?.autoCollectCategoryIds ?? []))
        _budgetEnabled = State(initialValue: book?.budgetEnabled ?? false)
        _budgetText = State(initialValue: book?.budgetLimitAmount.map { String($0) } ?? "")
        _hasDateRange = State(initialValue: book?.startDate != nil)
        _startDate = State(initialValue: book?.startDate ?? Date())
        _endDate = State(initialValue: book?.endDate ?? Date())
        _members = State(initialValue: book?.participantNames.isEmpty == false ? (book?.participantNames ?? []) : ["我"])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账本名称", text: $name)
                    TextField("备注", text: $note)
                    Button { iconPickerExpanded.toggle() } label: {
                        HStack { Image(systemName: icon).foregroundStyle(Color(hex: color)); VStack(alignment: .leading) { Text("图标"); Text(icon).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: iconPickerExpanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                    if iconPickerExpanded {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(DisplayPalette.icons, id: \.self) { option in Button { icon = option } label: { Image(systemName: option).frame(width: 32, height: 32).background(icon == option ? Color(hex: color).opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("主题颜色").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                            ForEach(DisplayPalette.colors, id: \.self) { option in Button { color = option } label: { Circle().fill(Color(hex: option)).frame(width: 26, height: 26).overlay { if color == option { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } } }.buttonStyle(.plain) }
                        }
                    }
                    Text("图标和主题颜色仅影响界面展示，不影响记账逻辑。").font(.footnote).foregroundStyle(.secondary)
                    Toggle("置顶显示", isOn: $isPinned)
                }
                Section("账本期间") {
                    Toggle("限定账本期间", isOn: $hasDateRange)
                    if hasDateRange { DatePicker("开始日期", selection: $startDate, displayedComponents: .date); DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date) }
                }
                Section("预算") {
                    Toggle("启用账本预算", isOn: $budgetEnabled)
                    if budgetEnabled { TextField("预算金额", text: $budgetText).keyboardType(.decimalPad) }
                }
                Section("自动归集") {
                    Toggle("自动归集范围内流水", isOn: Binding(get: { autoCollectEnabled }, set: { enabled in
                        if enabled && !hasDateRange { autoCollectEnabled = false } else if enabled && !autoCollectEnabled { showAutoCollectSetup = true } else { autoCollectEnabled = enabled }
                    }))
                    if autoCollectEnabled {
                        Text("仅匹配账本时间范围内的支出流水；未选分类表示全部分类。") .font(.caption).foregroundStyle(.secondary)
                        NavigationLink { BookAutoCollectCategoryPicker(selectedIDs: $selectedCategoryIDs).environmentObject(store) } label: {
                            LabeledContent("自动归集分类", value: selectedCategoryIDs.isEmpty ? "全部分类" : "已选 \(selectedCategoryIDs.count) 项")
                        }
                    }
                }
                Section("共同记账成员") {
                    ForEach(members, id: \.self) { member in Text(member) }
                        .onDelete { members.remove(atOffsets: $0) }
                    HStack { TextField("成员昵称", text: $newMember); Button("添加") { let value = newMember.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty && !members.contains(value) { members.append(value); newMember = "" } } }
                }
            }
            .navigationTitle(book == nil ? "新建账本" : "编辑账本")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .task { if store.categories.isEmpty { await store.loadCategories() } }
            .sheet(isPresented: $showAutoCollectSetup) {
                NavigationStack { VStack(alignment: .leading, spacing: 18) { Text("开启自动归集").font(.title3.bold()); Text("保存后，新流水会按账本日期范围和分类规则归集。你也可以选择立即归集已有流水。").foregroundStyle(.secondary); Toggle("保存后主动归集一次已有流水", isOn: $collectExistingNow); Spacer(); HStack { Button("取消") { showAutoCollectSetup = false }; Spacer(); Button("开启") { autoCollectEnabled = true; showAutoCollectSetup = false }.buttonStyle(.borderedProminent) } }.padding().navigationTitle("开启自动归集").navigationBarTitleDisplayMode(.inline) }
            }
        }
    }

    private func save() async {
        let amount = budgetEnabled ? Double(budgetText) : nil
        let draft = BookDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon.isEmpty ? nil : icon, note: note.isEmpty ? nil : note, color: color.isEmpty ? nil : color, startDate: hasDateRange ? startDate : nil, endDate: hasDateRange ? endDate : nil, budgetLimitAmount: amount, budgetStartDate: hasDateRange ? startDate : nil, budgetEndDate: hasDateRange ? endDate : nil, autoCollectEnabled: autoCollectEnabled, participantNames: members, isPinned: isPinned, autoCollectCategoryIds: Array(selectedCategoryIDs).sorted())
        if let book { await store.updateBook(book.id, with: draft); if collectExistingNow { await store.collectTransactionsIntoBook(book.id) } } else { let id = await store.createBook(draft); if collectExistingNow { await store.collectTransactionsIntoBook(id) } }
        dismiss()
    }
}
private struct BookAutoCollectCategoryPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selectedIDs: Set<Int>
    var body: some View { List { Section { Button("全部分类") { selectedIDs.removeAll() }.foregroundStyle(selectedIDs.isEmpty ? .blue : .primary) }; Section("支出分类") { ForEach(store.selectableCategories(for: .expense)) { category in Button { if selectedIDs.contains(category.id) { selectedIDs.remove(category.id) } else { selectedIDs.insert(category.id) } } label: { HStack { Text(category.displayName); Spacer(); if selectedIDs.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.blue) } } } } } }.navigationTitle("自动归集分类") }
}
